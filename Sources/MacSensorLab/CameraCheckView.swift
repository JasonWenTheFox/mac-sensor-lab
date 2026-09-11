@preconcurrency import AVFoundation
import AppKit
import CoreAudio
import CoreMedia
import CoreVideo
import Foundation
import SwiftUI

enum CameraAuthorizationState: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
}

enum CameraCaptureTermination: Equatable, Sendable {
  case deviceDisconnected
  case sessionInterrupted
  case runtimeError
  case systemSleep
  case applicationTermination
  case invalidFrame
  case safetyLimitReached
}

enum CameraCheckFailure: Equatable, Sendable {
  case noSupportedLocalCamera
  case permissionRequestIncomplete
  case configurationFailed
  case startFailed
  case continuityBoundaryMissing
}

enum CameraCheckStatus: Equatable, Sendable {
  case idle
  case awaitingPermissionConfirmation
  case requestingPermission
  case starting
  case capturing
  case stopped
  case permissionDenied
  case permissionRestricted
  case sessionLimitReached
  case interrupted(CameraCaptureTermination)
  case failed(CameraCheckFailure)
}

enum CameraCaptureSessionError: Error {
  case alreadyRunning
  case noSupportedLocalCamera
  case permissionUnavailable
  case configurationFailed
  case continuityBoundaryMissing
}

final class CameraPreviewHandle: @unchecked Sendable {
  let session: AVCaptureSession

  init(session: AVCaptureSession) {
    self.session = session
  }
}

@MainActor
protocol CameraCaptureSession: AnyObject {
  func start(
    onStarted: @escaping @Sendable (Bool) -> Void,
    onObservation: @escaping @Sendable (CameraFrameObservation) -> Void,
    onTermination: @escaping @Sendable (CameraCaptureTermination) -> Void
  ) throws -> CameraPreviewHandle?
  func stop()
}

struct CameraAuthorizationClient: Sendable {
  let current: @MainActor @Sendable () -> CameraAuthorizationState
  let request: @MainActor @Sendable () async -> CameraAuthorizationState

  static let live = CameraAuthorizationClient(
    current: { systemCameraAuthorizationState() },
    request: {
      guard systemCameraAuthorizationState() == .notDetermined else {
        return systemCameraAuthorizationState()
      }
      return await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .video) { _ in
          continuation.resume(returning: systemCameraAuthorizationState())
        }
      }
    }
  )

  static let demo = CameraAuthorizationClient(
    current: { .authorized },
    request: { .authorized }
  )
}

private func systemCameraAuthorizationState() -> CameraAuthorizationState {
  switch AVCaptureDevice.authorizationStatus(for: .video) {
  case .notDetermined: .notDetermined
  case .authorized: .authorized
  case .denied: .denied
  case .restricted: .restricted
  @unknown default: .restricted
  }
}

private final class CameraFrameOutputDelegate: NSObject,
  AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable
{
  static let minimumAnalysisInterval = 0.1

  private let lock = NSLock()
  private let onObservation: @Sendable (CameraFrameObservation) -> Void
  private let onTermination: @Sendable (CameraCaptureTermination) -> Void
  private var active = true
  private var deliveredFrameCount: UInt64 = 0
  private var droppedFrameCount: UInt64 = 0
  private var lastAnalysisUptime: Double?

  init(
    onObservation: @escaping @Sendable (CameraFrameObservation) -> Void,
    onTermination: @escaping @Sendable (CameraCaptureTermination) -> Void
  ) {
    self.onObservation = onObservation
    self.onTermination = onTermination
  }

  var isActive: Bool {
    lock.withLock { active }
  }

  func invalidate() {
    lock.withLock { active = false }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let uptime = ProcessInfo.processInfo.systemUptime
    let counts: (delivered: UInt64, dropped: UInt64)? = lock.withLock {
      guard active, deliveredFrameCount < CameraFrameObservation.maximumFrameCount else {
        return nil
      }
      deliveredFrameCount += 1
      guard
        lastAnalysisUptime == nil
          || uptime - (lastAnalysisUptime ?? uptime) >= Self.minimumAnalysisInterval
      else { return (0, 0) }
      lastAnalysisUptime = uptime
      return (deliveredFrameCount, droppedFrameCount)
    }
    guard let counts else {
      terminate(.safetyLimitReached)
      return
    }
    guard counts.delivered > 0 else { return }

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
      CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
    else {
      terminate(.invalidFrame)
      return
    }

    let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    guard lockResult == kCVReturnSuccess else {
      terminate(.invalidFrame)
      return
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let (byteCount, byteCountOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
    guard !byteCountOverflow,
      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
      let analysis = CameraFrameAnalyzer.analyzeBGRA(
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        byteCount: byteCount,
        byteAt: { baseAddress.load(fromByteOffset: $0, as: UInt8.self) }
      ),
      let observation = CameraFrameObservation(
        deliveredFrameCount: counts.delivered,
        droppedFrameCount: counts.dropped,
        observationUptimeSeconds: uptime,
        width: width,
        height: height,
        analysis: analysis
      )
    else {
      terminate(.invalidFrame)
      return
    }
    guard isActive else { return }
    onObservation(observation)
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didDrop sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let exceededLimit = lock.withLock {
      guard active else { return false }
      guard droppedFrameCount < CameraFrameObservation.maximumFrameCount else { return true }
      droppedFrameCount += 1
      return false
    }
    if exceededLimit {
      terminate(.safetyLimitReached)
    }
  }

  private func terminate(_ reason: CameraCaptureTermination) {
    let shouldNotify = lock.withLock {
      guard active else { return false }
      active = false
      return true
    }
    if shouldNotify {
      onTermination(reason)
    }
  }
}

@MainActor
final class SystemCameraCaptureSession: CameraCaptureSession {
  private struct ObserverRegistration {
    let center: NotificationCenter
    let token: NSObjectProtocol
  }

  private struct Resources {
    let session: AVCaptureSession
    let output: AVCaptureVideoDataOutput
    let delegate: CameraFrameOutputDelegate
    let observers: [ObserverRegistration]
  }

  private static let legacyContinuityCaptureTransport: UInt32 = 0x6363_6170
  private let sessionQueue = DispatchQueue(label: "dev.macsensorlab.camera-session")
  private let sampleQueue = DispatchQueue(label: "dev.macsensorlab.camera-samples")
  private var resources: Resources?

  func start(
    onStarted: @escaping @Sendable (Bool) -> Void,
    onObservation: @escaping @Sendable (CameraFrameObservation) -> Void,
    onTermination: @escaping @Sendable (CameraCaptureTermination) -> Void
  ) throws -> CameraPreviewHandle? {
    guard resources == nil else { throw CameraCaptureSessionError.alreadyRunning }
    guard
      Bundle.main.object(forInfoDictionaryKey: "NSCameraUseContinuityCameraDeviceType") as? Bool
        == true
    else { throw CameraCaptureSessionError.continuityBoundaryMissing }
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
      throw CameraCaptureSessionError.permissionUnavailable
    }

    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .external],
      mediaType: .video,
      position: .unspecified
    )
    guard let device = discovery.devices.first(where: Self.isSupportedLocalCamera) else {
      throw CameraCaptureSessionError.noSupportedLocalCamera
    }

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: device)
    } catch {
      throw CameraCaptureSessionError.configurationFailed
    }

    let session = AVCaptureSession()
    let output = AVCaptureVideoDataOutput()
    let delegate = CameraFrameOutputDelegate(
      onObservation: onObservation,
      onTermination: onTermination
    )
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    output.setSampleBufferDelegate(delegate, queue: sampleQueue)

    session.beginConfiguration()
    defer { session.commitConfiguration() }
    if session.canSetSessionPreset(.medium) {
      session.sessionPreset = .medium
    } else if session.canSetSessionPreset(.low) {
      session.sessionPreset = .low
    } else {
      throw CameraCaptureSessionError.configurationFailed
    }
    guard session.canAddInput(input), session.canAddOutput(output) else {
      throw CameraCaptureSessionError.configurationFailed
    }
    session.addInput(input)
    session.addOutput(output)

    let observers = installLifecycleObservers(
      session: session,
      device: device,
      onTermination: onTermination
    )
    resources = Resources(
      session: session,
      output: output,
      delegate: delegate,
      observers: observers
    )

    sessionQueue.async {
      guard delegate.isActive else { return }
      session.startRunning()
      let started = session.isRunning && delegate.isActive
      if !started, session.isRunning {
        session.stopRunning()
      }
      onStarted(started)
    }
    return CameraPreviewHandle(session: session)
  }

  func stop() {
    guard let resources else { return }
    self.resources = nil
    resources.delegate.invalidate()
    resources.output.setSampleBufferDelegate(nil, queue: nil)
    for observer in resources.observers {
      observer.center.removeObserver(observer.token)
    }
    let session = resources.session
    sessionQueue.async {
      if session.isRunning {
        session.stopRunning()
      }
    }
  }

  private static func isSupportedLocalCamera(_ device: AVCaptureDevice) -> Bool {
    guard device.deviceType == .builtInWideAngleCamera || device.deviceType == .external else {
      return false
    }
    let transport = UInt32(bitPattern: device.transportType)
    return transport != kAudioDeviceTransportTypeContinuityCaptureWired
      && transport != kAudioDeviceTransportTypeContinuityCaptureWireless
      && transport != legacyContinuityCaptureTransport
  }

  private func installLifecycleObservers(
    session: AVCaptureSession,
    device: AVCaptureDevice,
    onTermination: @escaping @Sendable (CameraCaptureTermination) -> Void
  ) -> [ObserverRegistration] {
    let center = NotificationCenter.default
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    return [
      ObserverRegistration(
        center: center,
        token: center.addObserver(
          forName: AVCaptureDevice.wasDisconnectedNotification,
          object: device,
          queue: nil
        ) { _ in onTermination(.deviceDisconnected) }
      ),
      ObserverRegistration(
        center: center,
        token: center.addObserver(
          forName: AVCaptureSession.wasInterruptedNotification,
          object: session,
          queue: nil
        ) { _ in onTermination(.sessionInterrupted) }
      ),
      ObserverRegistration(
        center: center,
        token: center.addObserver(
          forName: AVCaptureSession.runtimeErrorNotification,
          object: session,
          queue: nil
        ) { _ in onTermination(.runtimeError) }
      ),
      ObserverRegistration(
        center: workspaceCenter,
        token: workspaceCenter.addObserver(
          forName: NSWorkspace.willSleepNotification,
          object: nil,
          queue: nil
        ) { _ in onTermination(.systemSleep) }
      ),
      ObserverRegistration(
        center: center,
        token: center.addObserver(
          forName: NSApplication.willTerminateNotification,
          object: nil,
          queue: nil
        ) { _ in onTermination(.applicationTermination) }
      ),
    ]
  }
}

@MainActor
final class DemoCameraCaptureSession: CameraCaptureSession {
  private var task: Task<Void, Never>?

  func start(
    onStarted: @escaping @Sendable (Bool) -> Void,
    onObservation: @escaping @Sendable (CameraFrameObservation) -> Void,
    onTermination: @escaping @Sendable (CameraCaptureTermination) -> Void
  ) throws -> CameraPreviewHandle? {
    guard task == nil else { throw CameraCaptureSessionError.alreadyRunning }
    onStarted(true)
    task = Task {
      var delivered: UInt64 = 0
      var elapsed = 0.0
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .milliseconds(100))
        } catch {
          return
        }
        delivered += 3
        elapsed += 0.1
        let phase = Double(delivered % 60) / 60
        let minimum = 0.08 + phase * 0.06
        let maximum = 0.78 + phase * 0.08
        let analysis = CameraFrameAnalysis(
          sampledPixelCount: 4_096,
          meanRelativeLuma: (minimum + maximum) / 2,
          minimumRelativeLuma: minimum,
          maximumRelativeLuma: maximum
        )
        guard
          let observation = CameraFrameObservation(
            deliveredFrameCount: delivered,
            droppedFrameCount: 0,
            observationUptimeSeconds: elapsed,
            width: 1_280,
            height: 720,
            analysis: analysis
          )
        else {
          onTermination(.invalidFrame)
          return
        }
        onObservation(observation)
      }
    }
    return nil
  }

  func stop() {
    task?.cancel()
    task = nil
  }
}

@MainActor
final class CameraCheckModel: ObservableObject {
  static let defaultMaximumSessionDuration: Duration = .seconds(120)
  static let maximumAnalyzedObservationCount: UInt64 = 20_000

  @Published private(set) var authorizationState: CameraAuthorizationState
  @Published private(set) var status = CameraCheckStatus.idle
  @Published private(set) var previewHandle: CameraPreviewHandle?
  @Published private(set) var latestObservation: CameraFrameObservation?
  @Published private(set) var analyzedObservationCount: UInt64 = 0
  @Published private(set) var observedDeliveryFrameRate: Double?

  let isDemoMode: Bool

  private let authorizationClient: CameraAuthorizationClient
  private let captureSession: any CameraCaptureSession
  private let maximumSessionDuration: Duration
  private var nextOperationID: UInt64 = 1
  private var activeOperationID: UInt64?
  private var permissionTask: Task<Void, Never>?
  private var sessionLimitTask: Task<Void, Never>?

  var isCapturing: Bool { status == .capturing }

  var canStart: Bool {
    switch status {
    case .awaitingPermissionConfirmation, .requestingPermission, .starting, .capturing,
      .permissionDenied, .permissionRestricted:
      false
    default:
      true
    }
  }

  init(
    isDemoMode: Bool = false,
    authorizationClient: CameraAuthorizationClient? = nil,
    captureSession: (any CameraCaptureSession)? = nil,
    maximumSessionDuration: Duration = defaultMaximumSessionDuration
  ) {
    self.isDemoMode = isDemoMode
    self.authorizationClient = authorizationClient ?? (isDemoMode ? .demo : .live)
    self.captureSession =
      captureSession
      ?? (isDemoMode ? DemoCameraCaptureSession() : SystemCameraCaptureSession())
    self.maximumSessionDuration = maximumSessionDuration
    self.authorizationState = self.authorizationClient.current()
    switch self.authorizationState {
    case .denied:
      status = .permissionDenied
    case .restricted:
      status = .permissionRestricted
    case .notDetermined, .authorized:
      break
    }
  }

  func refreshAuthorization() {
    guard activeOperationID == nil else { return }
    authorizationState = authorizationClient.current()
    if status == .idle || status == .permissionDenied || status == .permissionRestricted {
      switch authorizationState {
      case .authorized, .notDetermined:
        status = .idle
      case .denied:
        status = .permissionDenied
      case .restricted:
        status = .permissionRestricted
      }
    }
  }

  func beginStart() {
    guard canStart else { return }
    authorizationState = authorizationClient.current()
    switch authorizationState {
    case .denied:
      status = .permissionDenied
    case .restricted:
      status = .permissionRestricted
    case .notDetermined, .authorized:
      if isDemoMode {
        guard let operationID = beginOperation() else { return }
        startCapture(operationID: operationID)
      } else {
        status = .awaitingPermissionConfirmation
      }
    }
  }

  func confirmPermissionAndStart() {
    guard status == .awaitingPermissionConfirmation,
      let operationID = beginOperation()
    else { return }

    switch authorizationState {
    case .authorized:
      startCapture(operationID: operationID)
    case .notDetermined:
      status = .requestingPermission
      let client = authorizationClient
      permissionTask = Task { [weak self] in
        let updatedState = await client.request()
        guard !Task.isCancelled, let self,
          self.activeOperationID == operationID
        else { return }
        self.permissionTask = nil
        self.authorizationState = updatedState
        switch updatedState {
        case .authorized:
          self.startCapture(operationID: operationID)
        case .denied:
          self.activeOperationID = nil
          self.status = .permissionDenied
        case .notDetermined:
          self.activeOperationID = nil
          self.status = .failed(.permissionRequestIncomplete)
        case .restricted:
          self.activeOperationID = nil
          self.status = .permissionRestricted
        }
      }
    case .denied:
      activeOperationID = nil
      status = .permissionDenied
    case .restricted:
      activeOperationID = nil
      status = .permissionRestricted
    }
  }

  func cancelPermissionExplanation() {
    guard status == .awaitingPermissionConfirmation else { return }
    status = .idle
  }

  func stop() {
    guard activeOperationID != nil else { return }
    stopCapture()
    status = .stopped
  }

  func leaveExperiment() {
    activeOperationID = nil
    permissionTask?.cancel()
    permissionTask = nil
    sessionLimitTask?.cancel()
    sessionLimitTask = nil
    captureSession.stop()
    previewHandle = nil
    clearSessionMetadata()
    authorizationState = authorizationClient.current()
    status = .idle
  }

  private func beginOperation() -> UInt64? {
    guard activeOperationID == nil, nextOperationID < .max else { return nil }
    let operationID = nextOperationID
    nextOperationID += 1
    activeOperationID = operationID
    return operationID
  }

  private func startCapture(operationID: UInt64) {
    guard activeOperationID == operationID else { return }
    status = .starting
    clearSessionMetadata()

    let startedHandler: @Sendable (Bool) -> Void = { [weak self] started in
      Task { @MainActor [weak self] in
        self?.receiveStarted(started, operationID: operationID)
      }
    }
    let observationHandler: @Sendable (CameraFrameObservation) -> Void = {
      [weak self] observation in
      Task { @MainActor [weak self] in
        self?.receive(observation, operationID: operationID)
      }
    }
    let terminationHandler: @Sendable (CameraCaptureTermination) -> Void = {
      [weak self] reason in
      Task { @MainActor [weak self] in
        self?.terminate(reason, operationID: operationID)
      }
    }

    do {
      previewHandle = try captureSession.start(
        onStarted: startedHandler,
        onObservation: observationHandler,
        onTermination: terminationHandler
      )
    } catch CameraCaptureSessionError.noSupportedLocalCamera {
      failStart(.noSupportedLocalCamera)
    } catch CameraCaptureSessionError.continuityBoundaryMissing {
      failStart(.continuityBoundaryMissing)
    } catch CameraCaptureSessionError.permissionUnavailable {
      authorizationState = authorizationClient.current()
      if authorizationState == .denied {
        failStart(nil, status: .permissionDenied)
      } else if authorizationState == .restricted {
        failStart(nil, status: .permissionRestricted)
      } else {
        failStart(.permissionRequestIncomplete)
      }
    } catch {
      failStart(.configurationFailed)
    }
  }

  private func receiveStarted(_ started: Bool, operationID: UInt64) {
    guard activeOperationID == operationID, status == .starting else { return }
    guard started else {
      failStart(.startFailed)
      return
    }
    status = .capturing
    startSessionLimit(operationID: operationID)
  }

  private func receive(_ observation: CameraFrameObservation, operationID: UInt64) {
    guard activeOperationID == operationID,
      status == .starting || status == .capturing
    else { return }

    if let previous = latestObservation {
      guard observation.deliveredFrameCount > previous.deliveredFrameCount,
        observation.droppedFrameCount >= previous.droppedFrameCount,
        observation.observationUptimeSeconds > previous.observationUptimeSeconds
      else {
        terminate(.invalidFrame, operationID: operationID)
        return
      }
      let elapsed = observation.observationUptimeSeconds - previous.observationUptimeSeconds
      let delivered = observation.deliveredFrameCount - previous.deliveredFrameCount
      let frameRate = Double(delivered) / elapsed
      guard frameRate.isFinite, frameRate > 0, frameRate <= 1_000 else {
        terminate(.invalidFrame, operationID: operationID)
        return
      }
      observedDeliveryFrameRate = frameRate
    }

    let (nextCount, overflow) = analyzedObservationCount.addingReportingOverflow(1)
    guard !overflow, nextCount <= Self.maximumAnalyzedObservationCount else {
      terminate(.safetyLimitReached, operationID: operationID)
      return
    }
    analyzedObservationCount = nextCount
    latestObservation = observation
  }

  private func terminate(_ reason: CameraCaptureTermination, operationID: UInt64) {
    guard activeOperationID == operationID else { return }
    stopCapture()
    status = .interrupted(reason)
  }

  private func startSessionLimit(operationID: UInt64) {
    let duration = maximumSessionDuration
    sessionLimitTask = Task { [weak self] in
      do {
        try await Task.sleep(for: duration)
      } catch {
        return
      }
      guard let self, self.activeOperationID == operationID else { return }
      self.stopCapture()
      self.status = .sessionLimitReached
    }
  }

  private func failStart(
    _ failure: CameraCheckFailure?,
    status explicitStatus: CameraCheckStatus? = nil
  ) {
    stopCapture()
    status = explicitStatus ?? .failed(failure ?? .configurationFailed)
  }

  private func stopCapture() {
    activeOperationID = nil
    permissionTask?.cancel()
    permissionTask = nil
    sessionLimitTask?.cancel()
    sessionLimitTask = nil
    captureSession.stop()
    previewHandle = nil
  }

  private func clearSessionMetadata() {
    latestObservation = nil
    analyzedObservationCount = 0
    observedDeliveryFrameRate = nil
  }
}

struct CameraCheckPanel: View {
  @ObservedObject var model: CameraCheckModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(L10n.text("Camera Check"), systemImage: "camera.viewfinder")
        .font(.title3.weight(.semibold))
      Text(
        L10n.text(
          "Starts a bounded local-camera preview only after a two-step action and derives relative digital luma and observed frame delivery in memory."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)

      statusLabel
      controls

      if let previewHandle = model.previewHandle {
        CameraPreviewSurface(handle: previewHandle)
          .frame(maxWidth: .infinity)
          .aspectRatio(16 / 9, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 10))
      } else if model.isDemoMode, model.isCapturing {
        CameraDemoPreviewSurface()
          .frame(maxWidth: .infinity)
          .aspectRatio(16 / 9, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 10))
      }

      if let observation = model.latestObservation {
        metrics(observation)
      }

      Text(
        L10n.text(
          "Raw BGRA frames are sampled only inside the capture callback and immediately reduced to at most 4,096 relative-luma samples. No frame, recording, photo, audio, device identity, persistence, snapshot, diagnostics value, or export."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      Text(
        L10n.text(
          "Relative luma is an uncalibrated digital image statistic, not lux, exposure, ambient brightness, display brightness, or camera quality. The session stops after two minutes at most."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .confirmationDialog(
      L10n.text("Start Camera Check with local video input?"),
      isPresented: confirmationBinding,
      titleVisibility: .visible
    ) {
      Button(L10n.text("Continue to Camera Check")) {
        model.confirmPermissionAndStart()
      }
      Button(L10n.text("Cancel"), role: .cancel) {
        model.cancelPermissionExplanation()
      }
    } message: {
      Text(
        L10n.text(
          "If Camera access is undecided, macOS will ask now. Otherwise the bounded preview starts immediately. Frames remain in memory and are never saved or exported."
        )
      )
    }
    .onAppear { model.refreshAuthorization() }
    .onDisappear { model.leaveExperiment() }
  }

  private var confirmationBinding: Binding<Bool> {
    Binding(
      get: { model.status == .awaitingPermissionConfirmation },
      set: { isPresented in
        if !isPresented, model.status == .awaitingPermissionConfirmation {
          model.cancelPermissionExplanation()
        }
      }
    )
  }

  @ViewBuilder
  private var controls: some View {
    HStack(spacing: 10) {
      if model.isCapturing || model.status == .starting {
        Button(L10n.text("Stop Camera Check")) { model.stop() }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("camera-check-stop")
      } else {
        Button(L10n.text(model.isDemoMode ? "Run Demo Camera Check" : "Start Camera Check")) {
          model.beginStart()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canStart)
        .accessibilityIdentifier("camera-check-start")
      }

      if model.authorizationState == .denied || model.authorizationState == .restricted {
        Button(L10n.text("Check Permission Again")) { model.refreshAuthorization() }
          .accessibilityIdentifier("camera-check-refresh-permission")
      }
    }
  }

  private var statusLabel: some View {
    let content = statusContent
    return Label(content.text, systemImage: content.symbol)
      .font(.callout.weight(.medium))
      .foregroundStyle(content.color)
      .accessibilityIdentifier("camera-check-status")
  }

  private var statusContent: (text: String, symbol: String, color: Color) {
    switch model.status {
    case .idle:
      if model.isDemoMode {
        (L10n.text("Idle — demo mode will not access the camera."), "testtube.2", .secondary)
      } else {
        (L10n.text("Idle — camera input has not started."), "pause.circle", .secondary)
      }
    case .awaitingPermissionConfirmation:
      (
        L10n.text("Review the camera privacy explanation before continuing."), "hand.raised",
        .orange
      )
    case .requestingPermission:
      (L10n.text("Waiting for the macOS Camera decision…"), "hand.raised", .blue)
    case .starting:
      (L10n.text("Starting the bounded camera session…"), "circle.dashed", .blue)
    case .capturing:
      (L10n.text("Previewing and reducing frames in memory."), "checkmark.circle", .green)
    case .stopped:
      (
        L10n.text("Camera Check stopped; bounded derived values remain until this page is left."),
        "stop.circle", .secondary
      )
    case .permissionDenied:
      (
        L10n.text(
          "Camera access is denied. Change it in System Settings if desired, then check again."
        ),
        "hand.raised.slash", .orange
      )
    case .permissionRestricted:
      (L10n.text("Camera access is restricted by the current system policy."), "lock", .orange)
    case .sessionLimitReached:
      (L10n.text("Camera Check stopped at the two-minute safety limit."), "timer", .orange)
    case .interrupted(let reason):
      (interruptionText(reason), "exclamationmark.triangle", .orange)
    case .failed(let failure):
      (failureText(failure), "xmark.circle", .orange)
    }
  }

  private func interruptionText(_ reason: CameraCaptureTermination) -> String {
    switch reason {
    case .deviceDisconnected:
      L10n.text("Camera Check stopped because the selected local camera disconnected.")
    case .sessionInterrupted:
      L10n.text("Camera Check stopped because macOS interrupted the capture session.")
    case .runtimeError:
      L10n.text("Camera Check stopped after a capture-session error.")
    case .systemSleep:
      L10n.text("Camera Check stopped before the Mac went to sleep.")
    case .applicationTermination:
      L10n.text("Camera Check stopped because the app is closing.")
    case .invalidFrame:
      L10n.text("Camera Check stopped after an invalid or unsupported frame.")
    case .safetyLimitReached:
      L10n.text("Camera Check stopped because a frame counter exceeded its safety limit.")
    }
  }

  private func failureText(_ failure: CameraCheckFailure) -> String {
    switch failure {
    case .noSupportedLocalCamera:
      L10n.text("No supported local built-in or external camera was available.")
    case .permissionRequestIncomplete:
      L10n.text("The Camera permission request did not produce an authorized state.")
    case .configurationFailed:
      L10n.text("The local camera session could not be configured.")
    case .startFailed:
      L10n.text("The local camera session could not start.")
    case .continuityBoundaryMissing:
      L10n.text(
        "Camera Check stopped because the Continuity Camera classification boundary is missing.")
    }
  }

  private func metrics(_ observation: CameraFrameObservation) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
      CameraCheckMetric(
        label: L10n.text("Observed frame size"),
        value: "\(observation.width) × \(observation.height) px"
      )
      CameraCheckMetric(
        label: L10n.text("Delivered frames"),
        value: String(observation.deliveredFrameCount)
      )
      CameraCheckMetric(
        label: L10n.text("Output-dropped frames"),
        value: String(observation.droppedFrameCount)
      )
      CameraCheckMetric(
        label: L10n.text("Analyzed observations"),
        value: String(model.analyzedObservationCount)
      )
      CameraCheckMetric(
        label: L10n.text("Observed delivery rate"),
        value: model.observedDeliveryFrameRate.map {
          "\($0.formatted(.number.precision(.fractionLength(1)))) fps"
        } ?? L10n.text("Waiting for another observation")
      )
      CameraCheckMetric(
        label: L10n.text("Sampled relative luma"),
        value: observation.analysis.meanRelativeLuma.formatted(
          .percent.precision(.fractionLength(1))
        )
      )
      CameraCheckMetric(
        label: L10n.text("Sampled luma span"),
        value: observation.analysis.sampledContrastSpan.formatted(
          .percent.precision(.fractionLength(1))
        )
      )
      CameraCheckMetric(
        label: L10n.text("Pixels sampled per analysis"),
        value: String(observation.analysis.sampledPixelCount)
      )
    }
  }
}

private struct CameraCheckMetric: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.weight(.semibold))
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(8)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
  }
}

private struct CameraDemoPreviewSurface: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [.black, .gray.opacity(0.7), .blue.opacity(0.45)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Text(L10n.text("Synthetic demo frame — no camera access"))
        .font(.headline)
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
    .accessibilityIdentifier("camera-check-demo-preview")
  }
}

private struct CameraPreviewSurface: NSViewRepresentable {
  let handle: CameraPreviewHandle

  func makeNSView(context: Context) -> CameraPreviewNSView {
    let view = CameraPreviewNSView()
    view.previewLayer.session = handle.session
    return view
  }

  func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
    if nsView.previewLayer.session !== handle.session {
      nsView.previewLayer.session = handle.session
    }
  }

  static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: Void) {
    nsView.previewLayer.session = nil
  }
}

private final class CameraPreviewNSView: NSView {
  let previewLayer = AVCaptureVideoPreviewLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    previewLayer.videoGravity = .resizeAspect
    layer?.addSublayer(previewLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    previewLayer.frame = bounds
  }
}
