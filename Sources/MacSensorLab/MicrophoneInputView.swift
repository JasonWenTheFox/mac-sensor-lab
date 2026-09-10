import AVFoundation
import AppKit
import Charts
import Combine
import Foundation
import SwiftUI

enum MicrophoneAuthorizationState: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
}

enum MicrophoneCaptureTermination: Equatable, Sendable {
  case configurationChanged
  case systemSleep
  case applicationTermination
  case invalidBuffer
}

enum MicrophoneInputFailure: Equatable, Sendable {
  case inputUnavailable
  case permissionRequestIncomplete
  case startFailed
  case safetyLimitReached
}

enum MicrophoneInputStatus: Equatable, Sendable {
  case idle
  case awaitingPermissionConfirmation
  case requestingPermission
  case starting
  case capturing
  case stopped
  case permissionDenied
  case permissionRestricted
  case sessionLimitReached
  case interrupted(MicrophoneCaptureTermination)
  case failed(MicrophoneInputFailure)
}

struct MicrophonePCMFormatMetadata: Equatable, Sendable {
  static let maximumSampleRate = 768_000.0
  static let maximumChannelCount = 64

  let sampleRate: Double
  let channelCount: Int

  init?(sampleRate: Double, channelCount: Int) {
    guard sampleRate.isFinite,
      (1...Self.maximumSampleRate).contains(sampleRate),
      (1...Self.maximumChannelCount).contains(channelCount)
    else { return nil }
    self.sampleRate = sampleRate
    self.channelCount = channelCount
  }
}

struct MicrophonePCMObservation: Equatable, Sendable {
  static let maximumFrameCount = 65_536

  let frameCount: Int
  let format: MicrophonePCMFormatMetadata
  let analysis: MicrophonePCMAnalysis

  init?(
    frameCount: Int,
    sampleRate: Double,
    channelCount: Int,
    analysis: MicrophonePCMAnalysis
  ) {
    guard (1...Self.maximumFrameCount).contains(frameCount),
      let format = MicrophonePCMFormatMetadata(
        sampleRate: sampleRate,
        channelCount: channelCount
      )
    else { return nil }
    self.frameCount = frameCount
    self.format = format
    self.analysis = analysis
  }
}

enum MicrophoneCaptureSessionError: Error {
  case alreadyRunning
  case inputUnavailable
  case startFailed
}

@MainActor
protocol MicrophoneCaptureSession: AnyObject {
  func start(
    onObservation: @escaping @Sendable (MicrophonePCMObservation) -> Void,
    onTermination: @escaping @Sendable (MicrophoneCaptureTermination) -> Void
  ) throws -> MicrophonePCMFormatMetadata
  func stop()
}

struct MicrophoneAuthorizationClient: Sendable {
  let current: @MainActor @Sendable () -> MicrophoneAuthorizationState
  let request: @MainActor @Sendable () async -> MicrophoneAuthorizationState

  static let live = MicrophoneAuthorizationClient(
    current: { systemMicrophoneAuthorizationState() },
    request: {
      guard systemMicrophoneAuthorizationState() == .notDetermined else {
        return systemMicrophoneAuthorizationState()
      }
      return await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { _ in
          continuation.resume(returning: systemMicrophoneAuthorizationState())
        }
      }
    }
  )

  static let demo = MicrophoneAuthorizationClient(
    current: { .authorized },
    request: { .authorized }
  )
}

private func systemMicrophoneAuthorizationState() -> MicrophoneAuthorizationState {
  switch AVCaptureDevice.authorizationStatus(for: .audio) {
  case .notDetermined: .notDetermined
  case .authorized: .authorized
  case .denied: .denied
  case .restricted: .restricted
  @unknown default: .restricted
  }
}

@MainActor
final class SystemMicrophoneCaptureSession: MicrophoneCaptureSession {
  static let tapBufferSize: AVAudioFrameCount = 1_024

  private struct ObserverRegistration {
    let center: NotificationCenter
    let token: NSObjectProtocol
  }

  private let engine = AVAudioEngine()
  private var observers: [ObserverRegistration] = []
  private var tapInstalled = false
  private(set) var isRunning = false

  func start(
    onObservation: @escaping @Sendable (MicrophonePCMObservation) -> Void,
    onTermination: @escaping @Sendable (MicrophoneCaptureTermination) -> Void
  ) throws -> MicrophonePCMFormatMetadata {
    guard !isRunning, !tapInstalled else {
      throw MicrophoneCaptureSessionError.alreadyRunning
    }

    let inputNode = engine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard
      format.commonFormat == .pcmFormatFloat32,
      let metadata = MicrophonePCMFormatMetadata(
        sampleRate: format.sampleRate,
        channelCount: Int(format.channelCount)
      )
    else {
      throw MicrophoneCaptureSessionError.inputUnavailable
    }

    installLifecycleObservers(onTermination: onTermination)
    let spectrumAnalyzer = MicrophoneSpectrumAnalyzer()
    let spectrumCadence = MicrophoneSpectrumCadence()
    inputNode.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format) {
      buffer, _ in
      let shouldAnalyzeSpectrum = spectrumCadence.shouldAnalyze(
        frameCount: Int(buffer.frameLength),
        sampleRate: buffer.format.sampleRate
      )
      guard
        let analysis = MicrophonePCMAnalyzer.analyze(
          buffer: buffer,
          spectrumAnalyzer: shouldAnalyzeSpectrum ? spectrumAnalyzer : nil
        ),
        let observation = MicrophonePCMObservation(
          frameCount: Int(buffer.frameLength),
          sampleRate: buffer.format.sampleRate,
          channelCount: Int(buffer.format.channelCount),
          analysis: analysis
        )
      else {
        onTermination(.invalidBuffer)
        return
      }
      onObservation(observation)
    }
    tapInstalled = true
    engine.prepare()

    do {
      try engine.start()
      isRunning = true
      return metadata
    } catch {
      cleanup()
      throw MicrophoneCaptureSessionError.startFailed
    }
  }

  func stop() {
    cleanup()
  }

  private func installLifecycleObservers(
    onTermination: @escaping @Sendable (MicrophoneCaptureTermination) -> Void
  ) {
    let center = NotificationCenter.default
    observers.append(
      ObserverRegistration(
        center: center,
        token: center.addObserver(
          forName: .AVAudioEngineConfigurationChange,
          object: engine,
          queue: nil
        ) { _ in
          onTermination(.configurationChanged)
        }
      )
    )
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    observers.append(
      ObserverRegistration(
        center: workspaceCenter,
        token: workspaceCenter.addObserver(
          forName: NSWorkspace.willSleepNotification,
          object: nil,
          queue: nil
        ) { _ in
          onTermination(.systemSleep)
        }
      )
    )
    observers.append(
      ObserverRegistration(
        center: center,
        token: center.addObserver(
          forName: NSApplication.willTerminateNotification,
          object: nil,
          queue: nil
        ) { _ in
          onTermination(.applicationTermination)
        }
      )
    )
  }

  private func cleanup() {
    for observer in observers {
      observer.center.removeObserver(observer.token)
    }
    observers.removeAll(keepingCapacity: true)

    if tapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    if engine.isRunning {
      engine.stop()
    }
    engine.reset()
    isRunning = false
  }
}

@MainActor
final class DemoMicrophoneCaptureSession: MicrophoneCaptureSession {
  private var task: Task<Void, Never>?

  func start(
    onObservation: @escaping @Sendable (MicrophonePCMObservation) -> Void,
    onTermination: @escaping @Sendable (MicrophoneCaptureTermination) -> Void
  ) throws -> MicrophonePCMFormatMetadata {
    guard task == nil else { throw MicrophoneCaptureSessionError.alreadyRunning }
    guard let format = MicrophonePCMFormatMetadata(sampleRate: 48_000, channelCount: 2) else {
      throw MicrophoneCaptureSessionError.inputUnavailable
    }
    let demoSamples = (0..<1_024).map { frame in
      Float(0.25 * sin(2 * Double.pi * Double(frame) / 64))
    }
    let spectrumAnalyzer = MicrophoneSpectrumAnalyzer()
    let spectrumCadence = MicrophoneSpectrumCadence()
    guard
      let baseAnalysis = MicrophonePCMAnalyzer.analyze(
        channels: [demoSamples, demoSamples]
      ),
      let spectrumAnalysis = MicrophonePCMAnalyzer.analyze(
        channels: [demoSamples, demoSamples],
        sampleRate: format.sampleRate,
        spectrumAnalyzer: spectrumAnalyzer
      )
    else {
      throw MicrophoneCaptureSessionError.inputUnavailable
    }

    task = Task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .milliseconds(80))
        } catch {
          return
        }
        guard
          let observation = MicrophonePCMObservation(
            frameCount: 1_024,
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            analysis: spectrumCadence.shouldAnalyze(
              frameCount: 1_024,
              sampleRate: format.sampleRate
            ) ? spectrumAnalysis : baseAnalysis
          )
        else {
          onTermination(.invalidBuffer)
          return
        }
        onObservation(observation)
      }
    }
    return format
  }

  func stop() {
    task?.cancel()
    task = nil
  }
}

@MainActor
final class MicrophoneInputModel: ObservableObject {
  static let defaultMaximumSessionDuration: Duration = .seconds(300)
  static let maximumObservationCount: UInt64 = 1_000_000
  static let maximumTotalFrameCount: UInt64 = 500_000_000
  static let maximumLevelHistoryCount = 300
  static let defaultMinimumLevelHistoryInterval = 0.08

  @Published private(set) var authorizationState: MicrophoneAuthorizationState
  @Published private(set) var status = MicrophoneInputStatus.idle
  @Published private(set) var format: MicrophonePCMFormatMetadata?
  @Published private(set) var observationCount: UInt64 = 0
  @Published private(set) var totalFrameCount: UInt64 = 0
  @Published private(set) var latestAnalysis: MicrophonePCMAnalysis?
  @Published private(set) var latestSpectrum: MicrophoneSpectrumAnalysis?
  @Published private(set) var levelHistory: [MicrophoneLevelPoint] = []

  let isDemoMode: Bool

  private let authorizationClient: MicrophoneAuthorizationClient
  private let captureSession: any MicrophoneCaptureSession
  private let maximumSessionDuration: Duration
  private let minimumLevelHistoryInterval: Double
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
    authorizationClient: MicrophoneAuthorizationClient? = nil,
    captureSession: (any MicrophoneCaptureSession)? = nil,
    maximumSessionDuration: Duration = defaultMaximumSessionDuration,
    minimumLevelHistoryInterval: Double = defaultMinimumLevelHistoryInterval
  ) {
    self.isDemoMode = isDemoMode
    self.authorizationClient = authorizationClient ?? (isDemoMode ? .demo : .live)
    self.captureSession =
      captureSession
      ?? (isDemoMode ? DemoMicrophoneCaptureSession() : SystemMicrophoneCaptureSession())
    self.maximumSessionDuration = maximumSessionDuration
    self.minimumLevelHistoryInterval = max(0, minimumLevelHistoryInterval)
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
    case .notDetermined:
      status = .awaitingPermissionConfirmation
    case .authorized:
      guard let operationID = beginOperation() else { return }
      startCapture(operationID: operationID)
    case .denied:
      status = .permissionDenied
    case .restricted:
      status = .permissionRestricted
    }
  }

  func confirmPermissionAndStart() {
    guard status == .awaitingPermissionConfirmation,
      let operationID = beginOperation()
    else { return }
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

    let observationHandler: @Sendable (MicrophonePCMObservation) -> Void = {
      [weak self] observation in
      Task { @MainActor [weak self] in
        self?.receive(observation, operationID: operationID)
      }
    }
    let terminationHandler: @Sendable (MicrophoneCaptureTermination) -> Void = {
      [weak self] reason in
      Task { @MainActor [weak self] in
        self?.terminate(reason, operationID: operationID)
      }
    }

    do {
      format = try captureSession.start(
        onObservation: observationHandler,
        onTermination: terminationHandler
      )
      status = .capturing
      startSessionLimit(operationID: operationID)
    } catch MicrophoneCaptureSessionError.inputUnavailable {
      activeOperationID = nil
      status = .failed(.inputUnavailable)
    } catch {
      captureSession.stop()
      activeOperationID = nil
      status = .failed(.startFailed)
    }
  }

  private func receive(_ observation: MicrophonePCMObservation, operationID: UInt64) {
    guard activeOperationID == operationID,
      status == .capturing || status == .starting,
      observation.format == format
    else {
      if activeOperationID == operationID {
        terminate(.configurationChanged, operationID: operationID)
      }
      return
    }

    let (nextObservationCount, observationOverflow) = observationCount.addingReportingOverflow(1)
    let (nextFrameCount, frameOverflow) = totalFrameCount.addingReportingOverflow(
      UInt64(observation.frameCount)
    )
    guard !observationOverflow, !frameOverflow,
      nextObservationCount <= Self.maximumObservationCount,
      nextFrameCount <= Self.maximumTotalFrameCount
    else {
      stopCapture()
      status = .failed(.safetyLimitReached)
      return
    }
    observationCount = nextObservationCount
    totalFrameCount = nextFrameCount
    latestAnalysis = observation.analysis
    if let spectrum = observation.analysis.spectrum {
      latestSpectrum = spectrum
    }
    recordLevelPoint(
      observation.analysis,
      id: nextObservationCount,
      elapsedSeconds: Double(nextFrameCount) / observation.format.sampleRate
    )
  }

  private func terminate(
    _ reason: MicrophoneCaptureTermination,
    operationID: UInt64
  ) {
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

  private func stopCapture() {
    activeOperationID = nil
    permissionTask?.cancel()
    permissionTask = nil
    sessionLimitTask?.cancel()
    sessionLimitTask = nil
    captureSession.stop()
  }

  private func clearSessionMetadata() {
    format = nil
    observationCount = 0
    totalFrameCount = 0
    latestAnalysis = nil
    latestSpectrum = nil
    levelHistory.removeAll(keepingCapacity: true)
  }

  private func recordLevelPoint(
    _ analysis: MicrophonePCMAnalysis,
    id: UInt64,
    elapsedSeconds: Double
  ) {
    guard
      let point = MicrophoneLevelPoint(
        id: id,
        elapsedSeconds: elapsedSeconds,
        analysis: analysis
      )
    else { return }

    if let lastPoint = levelHistory.last,
      elapsedSeconds - lastPoint.elapsedSeconds < minimumLevelHistoryInterval
    {
      levelHistory[levelHistory.count - 1] =
        MicrophoneLevelPoint(
          id: lastPoint.id,
          elapsedSeconds: elapsedSeconds,
          analysis: analysis
        ) ?? lastPoint
    } else {
      levelHistory.append(point)
      if levelHistory.count > Self.maximumLevelHistoryCount {
        levelHistory.removeFirst(levelHistory.count - Self.maximumLevelHistoryCount)
      }
    }
  }
}

struct MicrophoneInputPanel: View {
  @ObservedObject var model: MicrophoneInputModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(L10n.text("Sound Input Check"), systemImage: "mic.and.signal.meter")
        .font(.title3.weight(.semibold))
      Text(
        L10n.text(
          "Starts a bounded microphone session only after an explicit action and derives a waveform envelope, RMS, peak, dBFS, and a relative frequency spectrum in memory."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)

      statusLabel
      controls

      if let format = model.format {
        metrics(format)
      }
      if let analysis = model.latestAnalysis {
        signalMetrics(analysis)
        waveformChart(analysis)
      }
      if !model.levelHistory.isEmpty {
        levelHistoryChart
      }
      if let spectrum = model.latestSpectrum {
        spectrumMetrics(spectrum)
        spectrumChart(spectrum)
      }

      Text(
        L10n.text(
          "Raw PCM is inspected only inside the audio callback and immediately reduced to bounded derived values. No samples, recordings, device identity, persistence, snapshot, diagnostics values, or export."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      Text(
        L10n.text(
          "dBFS uses digital full scale 1.0; it is not dBA, sound-pressure level, or calibrated loudness. The history chart clips values below −96 dBFS, while exact digital silence is reported as −∞ dBFS. Spectrum values are relative to the current non-DC peak, not dBFS or SPL."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .confirmationDialog(
      L10n.text("Allow microphone input for Sound Input Check?"),
      isPresented: permissionConfirmationBinding,
      titleVisibility: .visible
    ) {
      Button(L10n.text("Continue to macOS Permission")) {
        model.confirmPermissionAndStart()
      }
      Button(L10n.text("Cancel"), role: .cancel) {
        model.cancelPermissionExplanation()
      }
    } message: {
      Text(
        L10n.text(
          "macOS will ask for microphone access. Capture begins only if you allow it; buffers stay in memory and are never saved or exported."
        )
      )
    }
    .onAppear { model.refreshAuthorization() }
    .onDisappear { model.leaveExperiment() }
  }

  private var permissionConfirmationBinding: Binding<Bool> {
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
      if model.isCapturing {
        Button(L10n.text("Stop Sound Input")) { model.stop() }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("sound-input-stop")
      } else {
        Button(L10n.text(model.isDemoMode ? "Run Demo Sound Input" : "Start Sound Input Check")) {
          model.beginStart()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canStart)
        .accessibilityIdentifier("sound-input-start")
      }

      if model.authorizationState == .denied || model.authorizationState == .restricted {
        Button(L10n.text("Check Permission Again")) { model.refreshAuthorization() }
          .accessibilityIdentifier("sound-input-refresh-permission")
      }
    }
  }

  private var statusLabel: some View {
    let content = statusContent
    return Label(content.text, systemImage: content.symbol)
      .font(.callout.weight(.medium))
      .foregroundStyle(content.color)
      .accessibilityIdentifier("sound-input-status")
  }

  private var statusContent: (text: String, symbol: String, color: Color) {
    switch model.status {
    case .idle:
      if model.isDemoMode {
        (L10n.text("Idle — demo mode will not access the microphone."), "testtube.2", .secondary)
      } else {
        (L10n.text("Idle — microphone input has not started."), "pause.circle", .secondary)
      }
    case .awaitingPermissionConfirmation:
      (L10n.text("Review the privacy explanation before continuing."), "hand.raised", .orange)
    case .requestingPermission:
      (L10n.text("Waiting for the macOS microphone decision…"), "hand.raised", .blue)
    case .starting:
      (L10n.text("Starting the bounded audio input session…"), "circle.dashed", .blue)
    case .capturing:
      (L10n.text("Analyzing PCM buffers in memory."), "checkmark.circle", .green)
    case .stopped:
      (
        L10n.text(
          "Sound input stopped; counters and bounded derived analysis remain until this page is left."
        ),
        "stop.circle", .secondary
      )
    case .permissionDenied:
      (
        L10n.text(
          "Microphone access is denied. Change it in System Settings if desired, then check again."),
        "hand.raised.slash", .orange
      )
    case .permissionRestricted:
      (L10n.text("Microphone access is restricted by the current system policy."), "lock", .orange)
    case .sessionLimitReached:
      (L10n.text("Sound input stopped at the five-minute safety limit."), "timer", .orange)
    case .interrupted(let reason):
      (interruptionText(reason), "exclamationmark.triangle", .orange)
    case .failed(let failure):
      (failureText(failure), "xmark.circle", .orange)
    }
  }

  private func interruptionText(_ reason: MicrophoneCaptureTermination) -> String {
    switch reason {
    case .configurationChanged:
      L10n.text("Sound input stopped because the audio-device configuration changed.")
    case .systemSleep:
      L10n.text("Sound input stopped before the Mac went to sleep.")
    case .applicationTermination:
      L10n.text("Sound input stopped because the app is closing.")
    case .invalidBuffer:
      L10n.text("Sound input stopped after an invalid PCM buffer.")
    }
  }

  private func failureText(_ failure: MicrophoneInputFailure) -> String {
    switch failure {
    case .inputUnavailable:
      L10n.text("No enabled microphone input format was available.")
    case .permissionRequestIncomplete:
      L10n.text("The microphone permission request did not produce a decision.")
    case .startFailed:
      L10n.text("The audio input session could not start.")
    case .safetyLimitReached:
      L10n.text("Sound input stopped because a counter exceeded its safety limit.")
    }
  }

  private func metrics(_ format: MicrophonePCMFormatMetadata) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
      MicrophoneInputMetric(
        label: L10n.text("PCM sample rate"),
        value: "\(format.sampleRate.formatted(.number.precision(.fractionLength(0...2)))) Hz"
      )
      MicrophoneInputMetric(
        label: L10n.text("PCM channels"),
        value: String(format.channelCount)
      )
      MicrophoneInputMetric(
        label: L10n.text("Observed buffers"),
        value: String(model.observationCount)
      )
      MicrophoneInputMetric(
        label: L10n.text("Observed PCM frames"),
        value: String(model.totalFrameCount)
      )
    }
  }

  private func signalMetrics(_ analysis: MicrophonePCMAnalysis) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
      MicrophoneInputMetric(
        label: L10n.text("RMS amplitude"),
        value: formatAmplitude(analysis.rootMeanSquareAmplitude)
      )
      MicrophoneInputMetric(
        label: L10n.text("Peak amplitude"),
        value: formatAmplitude(analysis.peakAmplitude)
      )
      MicrophoneInputMetric(
        label: L10n.text("RMS level"),
        value: formatDBFS(analysis.rootMeanSquareDBFS)
      )
      MicrophoneInputMetric(
        label: L10n.text("Peak level"),
        value: formatDBFS(analysis.peakDBFS)
      )
    }
  }

  private func waveformChart(_ analysis: MicrophonePCMAnalysis) -> some View {
    let amplitudeDomain = max(1, analysis.peakAmplitude)
    return VStack(alignment: .leading, spacing: 6) {
      Text(L10n.text("Latest waveform envelope"))
        .font(.callout.weight(.semibold))
      Text(
        L10n.text(
          "Up to 128 min/max bins from the latest buffer after averaging channels per frame."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      Chart(analysis.waveform) { bin in
        AreaMark(
          x: .value(L10n.text("Waveform bin"), bin.index),
          yStart: .value(L10n.text("Minimum amplitude"), bin.minimum),
          yEnd: .value(L10n.text("Maximum amplitude"), bin.maximum)
        )
        .foregroundStyle(.blue.opacity(0.45))
      }
      .chartYScale(domain: -amplitudeDomain...amplitudeDomain)
      .frame(height: 120)
      .accessibilityIdentifier("sound-input-waveform")
    }
  }

  private var levelHistoryChart: some View {
    let upperBound = max(0, model.levelHistory.map(\.peakDBFS).max() ?? 0)
    return VStack(alignment: .leading, spacing: 6) {
      Text(L10n.text("Bounded level history"))
        .font(.callout.weight(.semibold))
      HStack(spacing: 14) {
        Label(L10n.text("RMS dBFS"), systemImage: "circle.fill")
          .foregroundStyle(.blue)
        Label(L10n.text("Peak dBFS"), systemImage: "circle.fill")
          .foregroundStyle(.orange)
      }
      .font(.caption2)
      Chart(model.levelHistory) { point in
        LineMark(
          x: .value(L10n.text("Elapsed seconds"), point.elapsedSeconds),
          y: .value(L10n.text("RMS dBFS"), point.rootMeanSquareDBFS)
        )
        .foregroundStyle(.blue)
        LineMark(
          x: .value(L10n.text("Elapsed seconds"), point.elapsedSeconds),
          y: .value(L10n.text("Peak dBFS"), point.peakDBFS)
        )
        .foregroundStyle(.orange)
      }
      .chartYScale(domain: MicrophoneLevelPoint.displayFloorDBFS...upperBound)
      .frame(height: 140)
      .accessibilityIdentifier("sound-input-level-history")
    }
  }

  private func spectrumMetrics(_ spectrum: MicrophoneSpectrumAnalysis) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
      MicrophoneInputMetric(
        label: L10n.text("Spectrum FFT size"),
        value: String(spectrum.fftSize)
      )
      MicrophoneInputMetric(
        label: L10n.text("Frequency resolution"),
        value:
          "\(spectrum.frequencyResolutionHz.formatted(.number.precision(.fractionLength(1)))) Hz"
      )
      MicrophoneInputMetric(
        label: L10n.text("Strongest non-DC bin center"),
        value: formatStrongestFrequency(spectrum.strongestBinCenterFrequencyHz)
      )
    }
  }

  private func spectrumChart(_ spectrum: MicrophoneSpectrumAnalysis) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.text("Latest relative spectrum"))
        .font(.callout.weight(.semibold))
      Text(
        L10n.text(
          "The latest spectrum uses at most 2,048 recent channel-averaged frames, removes the mean, applies a Hann window, and reduces positive frequencies to at most 128 bands. It refreshes no faster than 10 Hz."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      Chart(spectrum.bins) { bin in
        AreaMark(
          x: .value(L10n.text("Frequency Hz"), bin.centerFrequencyHz),
          yStart: .value(L10n.text("Spectrum floor"), MicrophoneSpectrumAnalyzer.displayFloorDB),
          yEnd: .value(L10n.text("Relative magnitude dB"), bin.relativeMagnitudeDB)
        )
        .foregroundStyle(.purple.opacity(0.5))
      }
      .chartXScale(domain: 0...spectrum.nyquistFrequencyHz)
      .chartYScale(domain: MicrophoneSpectrumAnalyzer.displayFloorDB...0)
      .frame(height: 140)
      .accessibilityIdentifier("sound-input-spectrum")
      Text(
        L10n.text(
          "The strongest value is the center of a finite-resolution FFT bin. It does not identify a sound source, musical pitch, speech, or the surrounding environment."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  private func formatAmplitude(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(4)))
  }

  private func formatDBFS(_ value: Double?) -> String {
    guard let value else { return "−∞ dBFS" }
    return "\(value.formatted(.number.precision(.fractionLength(1)))) dBFS"
  }

  private func formatStrongestFrequency(_ value: Double?) -> String {
    guard let value else { return L10n.text("No non-DC spectral peak") }
    return "\(value.formatted(.number.precision(.fractionLength(1)))) Hz"
  }
}

private struct MicrophoneInputMetric: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.callout.weight(.semibold)).monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(8)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .combine)
  }
}
