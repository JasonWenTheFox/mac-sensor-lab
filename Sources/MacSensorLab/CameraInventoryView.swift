import Combine
import Foundation
import SensorCore
import SwiftUI

enum CameraInventoryStatus: Equatable {
  case idle
  case reading
  case ready
  case limited
  case empty
  case timedOutWaiting
  case failed(CameraInventoryFailure)
}

@MainActor
final class CameraInventoryModel: ObservableObject {
  typealias ReadOperation = @Sendable () async -> CameraInventoryOutcome

  static let defaultTimeout: Duration = .seconds(2)

  @Published private(set) var status = CameraInventoryStatus.idle
  @Published private(set) var result: CameraInventorySnapshot?
  @Published private(set) var isAwaitingResult = false
  @Published private(set) var isOperationInFlight = false

  private let operation: ReadOperation
  private let timeout: Duration
  private var nextOperationID: UInt64 = 1
  private var activeOperationID: UInt64?
  private var presentedOperationID: UInt64?
  private var readTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?

  var canStart: Bool {
    !isOperationInFlight
  }

  init(
    isDemoMode: Bool = false,
    timeout: Duration = defaultTimeout,
    operation: ReadOperation? = nil
  ) {
    self.timeout = timeout
    self.operation = operation ?? (isDemoMode ? Self.demoRead : Self.liveRead)
  }

  func start() {
    guard canStart, nextOperationID < .max else { return }

    let operationID = nextOperationID
    nextOperationID += 1
    activeOperationID = operationID
    presentedOperationID = operationID
    result = nil
    status = .reading
    isAwaitingResult = true
    isOperationInFlight = true

    let operation = self.operation
    readTask = Task { [weak self] in
      let outcome = await operation()
      guard let self else { return }
      self.operationFinished(operationID, outcome: outcome)
    }

    let timeout = self.timeout
    timeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(for: timeout)
      } catch {
        return
      }
      guard let self else { return }
      self.waitingTimedOut(operationID)
    }
  }

  func leaveInventory() {
    presentedOperationID = nil
    isAwaitingResult = false
    timeoutTask?.cancel()
    timeoutTask = nil
    result = nil
    status = .idle
  }

  private func operationFinished(_ operationID: UInt64, outcome: CameraInventoryOutcome) {
    guard activeOperationID == operationID else { return }

    activeOperationID = nil
    isOperationInFlight = false
    readTask = nil
    timeoutTask?.cancel()
    timeoutTask = nil

    guard presentedOperationID == operationID, isAwaitingResult else { return }
    presentedOperationID = nil
    isAwaitingResult = false
    switch outcome {
    case .success(let snapshot):
      result = snapshot
      if snapshot.devices.isEmpty {
        status = .empty
      } else if snapshot.isLimited {
        status = .limited
      } else {
        status = .ready
      }
    case .failure(let failure):
      result = nil
      status = .failed(failure)
    }
  }

  private func waitingTimedOut(_ operationID: UInt64) {
    guard activeOperationID == operationID, presentedOperationID == operationID else { return }
    presentedOperationID = nil
    isAwaitingResult = false
    timeoutTask = nil
    result = nil
    status = .timedOutWaiting
  }

  private static let liveRead: ReadOperation = {
    await CameraInventoryReader.read()
  }

  private static let demoRead: ReadOperation = {
    try? await Task.sleep(for: .milliseconds(250))
    return CameraInventoryReducer.reduce(
      devices: [
        CameraInventoryRawDevice(
          sourceIndex: 0,
          deviceType: .builtInWideAngle,
          positionRawValue: 2,
          transportRawValue: 0x626C_746E,
          formats: [
            CameraInventoryRawFormat(
              sourceIndex: 0,
              width: 1_920,
              height: 1_080,
              frameRateRanges: [
                CameraInventoryRawFrameRateRange(minimum: 24, maximum: 30),
                CameraInventoryRawFrameRateRange(minimum: 60, maximum: 60),
              ],
              autofocusSystemRawValue: 1,
              colorSpaceRawValues: [0, 1]
            ),
            CameraInventoryRawFormat(
              sourceIndex: 1,
              width: 1_280,
              height: 720,
              frameRateRanges: [
                CameraInventoryRawFrameRateRange(minimum: 30, maximum: 30)
              ],
              autofocusSystemRawValue: 1,
              colorSpaceRawValues: [0]
            ),
          ]
        ),
        CameraInventoryRawDevice(
          sourceIndex: 1,
          deviceType: .external,
          positionRawValue: 0,
          transportRawValue: 0x7573_6220,
          formats: [
            CameraInventoryRawFormat(
              sourceIndex: 0,
              width: 3_840,
              height: 2_160,
              frameRateRanges: [
                CameraInventoryRawFrameRateRange(minimum: 30, maximum: 30)
              ],
              autofocusSystemRawValue: 2,
              colorSpaceRawValues: [0, 1]
            )
          ]
        ),
      ]
    )
  }
}

struct CameraInventoryPanel: View {
  @ObservedObject var model: CameraInventoryModel
  let isDemoMode: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(L10n.text("Camera Capabilities"), systemImage: "video")
        .font(.title3.weight(.semibold))
      Text(
        L10n.text(
          "Discovers one bounded set of local camera formats only after you ask. No camera permission is requested and no device is opened."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)

      statusLabel

      HStack(spacing: 10) {
        let startLabel = L10n.text(
          isDemoMode ? "Load Demo Camera Capabilities" : "Read Camera Capabilities"
        )
        Button(startLabel) { model.start() }
          .disabled(!model.canStart)
          .accessibilityLabel(Text(startLabel))
          .accessibilityIdentifier("camera-inventory-start")

        if model.isAwaitingResult {
          ProgressView()
            .controlSize(.small)
        } else if model.isOperationInFlight {
          Text(L10n.text("Camera discovery may still be finishing."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let result = model.result {
        resultView(result)
      }

      Text(
        L10n.text(
          "No camera frames, audio, permission request, device identity, free text, persistence, history, diagnostics values, or export."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      Text(
        L10n.text(
          "Continuity Camera and Desk View are excluded by device type and transport classification."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .padding(16)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.quaternary, lineWidth: 1)
    }
  }

  private var statusLabel: some View {
    Label(statusText, systemImage: statusSymbol)
      .font(.callout.weight(.medium))
      .foregroundStyle(statusColor)
  }

  private var statusText: String {
    switch model.status {
    case .idle:
      L10n.text("Idle — camera capabilities have not been read this session.")
    case .reading:
      L10n.text("Reading bounded local camera capabilities…")
    case .ready:
      L10n.text("Camera capabilities are available on this page for this session.")
    case .limited:
      L10n.text("Camera capabilities are available with unsupported metadata omitted.")
    case .empty:
      L10n.text("No supported local camera was discovered.")
    case .timedOutWaiting:
      L10n.text("Stopped waiting after two seconds; any late result will be discarded.")
    case .failed(let failure):
      failureText(failure)
    }
  }

  private var statusSymbol: String {
    switch model.status {
    case .idle: "pause.circle"
    case .reading: "video.badge.ellipsis"
    case .ready: "checkmark.circle"
    case .empty: "minus.circle"
    case .limited, .timedOutWaiting, .failed: "exclamationmark.triangle"
    }
  }

  private var statusColor: Color {
    switch model.status {
    case .ready: .green
    case .reading: .blue
    case .idle, .empty: .secondary
    case .limited, .timedOutWaiting, .failed: .orange
    }
  }

  private func failureText(_ failure: CameraInventoryFailure) -> String {
    switch failure {
    case .continuityBoundaryMissing:
      L10n.text("The app bundle is missing its Continuity Camera classification boundary.")
    case .discoveryUnavailable:
      L10n.text("Camera capability discovery is temporarily unavailable.")
    case .safetyLimitReached:
      L10n.text("Camera metadata exceeded its safety limit and was not shown.")
    case .malformedData:
      L10n.text("Camera metadata changed shape or was malformed.")
    case .failed:
      L10n.text("Camera capability discovery failed without exposing system error text.")
    }
  }

  private func resultView(_ result: CameraInventorySnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        L10n.format(
          "%lld supported local cameras • %lld capability rows",
          Int64(result.devices.count),
          Int64(result.capabilityRowCount)
        )
      )
      .font(.headline.monospacedDigit())

      if result.isLimited {
        Text(
          L10n.format(
            "%lld excluded devices • %lld malformed or unknown fields omitted",
            Int64(result.discardedDeviceCount),
            Int64(result.malformedFieldCount)
          )
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }

      ForEach(result.devices) { device in
        deviceView(device)
      }
    }
  }

  private func deviceView(_ device: CameraInventoryDevice) -> some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 9) {
        CameraInventoryFactRow(
          label: L10n.text("Device type"),
          value: L10n.text(device.deviceType.displayName)
        )
        CameraInventoryFactRow(
          label: L10n.text("Position"),
          value: L10n.text(device.position.displayName)
        )
        CameraInventoryFactRow(
          label: L10n.text("Transport"),
          value: L10n.text(device.transport.displayName)
        )
        CameraInventoryFactRow(
          label: L10n.text("Reported formats"),
          value: String(device.reportedFormatCount)
        )

        if device.capabilities.isEmpty {
          Text(L10n.text("No valid capability rows were reported."))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(device.capabilities) { capability in
              capabilityView(capability)
            }
          }
        }
      }
      .padding(.top, 10)
    } label: {
      HStack {
        Text(L10n.format("Camera %lld", Int64(device.ordinal)))
          .font(.headline)
        Spacer()
        Text(
          L10n.format(
            "%lld capability rows",
            Int64(device.capabilities.count)
          )
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
  }

  private func capabilityView(_ capability: CameraInventoryCapability) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(
          L10n.format(
            "%lld × %lld",
            Int64(capability.width),
            Int64(capability.height)
          )
        )
        .font(.callout.weight(.semibold).monospacedDigit())
        Spacer()
        if capability.variantCount > 1 {
          Text(
            L10n.format(
              "%lld equivalent formats",
              Int64(capability.variantCount)
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      CameraInventoryFactRow(
        label: L10n.text("Frame rate range"),
        value: frameRateText(capability)
      )
      CameraInventoryFactRow(
        label: L10n.text("Autofocus system"),
        value: L10n.text(capability.autofocusSystem.displayName)
      )
      CameraInventoryFactRow(
        label: L10n.text("Color spaces"),
        value: capability.colorSpaces.isEmpty
          ? L10n.text("None reported")
          : capability.colorSpaces.map { L10n.text($0.displayName) }.joined(separator: ", ")
      )
    }
    .padding(.leading, 12)
    .padding(.vertical, 7)
    .overlay(alignment: .leading) {
      Rectangle().fill(.quaternary).frame(width: 2)
    }
  }

  private func frameRateText(_ capability: CameraInventoryCapability) -> String {
    let minimum = decimal(capability.minimumFrameRate)
    let maximum = decimal(capability.maximumFrameRate)
    if capability.minimumFrameRate == capability.maximumFrameRate {
      return L10n.format("%@ fps", minimum)
    }
    return L10n.format("%@–%@ fps", minimum, maximum)
  }

  private func decimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...3)))
  }
}

private struct CameraInventoryFactRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
    }
    .font(.caption)
  }
}
