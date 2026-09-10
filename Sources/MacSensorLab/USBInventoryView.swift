import Combine
import Foundation
import SensorCore
import SwiftUI

enum USBInventoryStatus: Equatable {
  case idle
  case reading
  case ready
  case limited
  case empty
  case timedOutWaiting
  case failed(USBInventoryFailure)
}

@MainActor
final class USBInventoryModel: ObservableObject {
  typealias ReadOperation = @Sendable () async -> USBInventoryOutcome

  static let defaultTimeout: Duration = .seconds(2)

  @Published private(set) var status = USBInventoryStatus.idle
  @Published private(set) var result: USBInventorySnapshot?
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

  private func operationFinished(_ operationID: UInt64, outcome: USBInventoryOutcome) {
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
      if snapshot.isLimited {
        status = .limited
      } else {
        status = snapshot.devices.isEmpty ? .empty : .ready
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
    await USBInventoryReader.read()
  }

  private static let demoRead: ReadOperation = {
    try? await Task.sleep(for: .milliseconds(250))
    return USBInventoryReducer.reduce(
      devices: [
        USBInventoryRawDevice(
          sourceIndex: 10,
          vendorID: .integer(0x05AC),
          productID: .integer(0x1001),
          deviceReleaseNumber: .integer(0x0100),
          deviceClass: .integer(9),
          deviceSubClass: .integer(0),
          deviceProtocol: .integer(1),
          currentConfiguration: .integer(1),
          connectionSpeed: .integer(3)
        ),
        USBInventoryRawDevice(
          sourceIndex: 20,
          parentSourceIndex: 10,
          vendorID: .integer(0x1234),
          productID: .integer(0x5678),
          deviceReleaseNumber: .integer(0x0210),
          deviceClass: .integer(0),
          deviceSubClass: .integer(0),
          deviceProtocol: .integer(0),
          currentConfiguration: .integer(1),
          connectionSpeed: .integer(4)
        ),
        USBInventoryRawDevice(
          sourceIndex: 30,
          vendorID: .integer(0x2345),
          productID: .integer(0x0001),
          deviceReleaseNumber: .integer(0x0002),
          deviceClass: .integer(1),
          deviceSubClass: .integer(0),
          deviceProtocol: .integer(0),
          currentConfiguration: .integer(1),
          connectionSpeed: .integer(2)
        ),
      ],
      interfaces: [
        USBInventoryRawInterface(
          sourceIndex: 100,
          parentDeviceSourceIndex: 20,
          interfaceNumber: .integer(0),
          interfaceClass: .integer(3),
          interfaceSubClass: .integer(1),
          interfaceProtocol: .integer(2),
          alternateSetting: .integer(0)
        ),
        USBInventoryRawInterface(
          sourceIndex: 101,
          parentDeviceSourceIndex: 20,
          interfaceNumber: .integer(1),
          interfaceClass: .integer(8),
          interfaceSubClass: .integer(6),
          interfaceProtocol: .integer(80),
          alternateSetting: .integer(0)
        ),
        USBInventoryRawInterface(
          sourceIndex: 102,
          parentDeviceSourceIndex: 30,
          interfaceNumber: .integer(0),
          interfaceClass: .integer(1),
          interfaceSubClass: .integer(2),
          interfaceProtocol: .integer(0),
          alternateSetting: .integer(0)
        ),
      ]
    )
  }
}

struct USBInventoryPanel: View {
  @ObservedObject var model: USBInventoryModel
  let isDemoMode: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(L10n.text("USB Device Tree"), systemImage: "point.3.connected.trianglepath.dotted")
        .font(.title3.weight(.semibold))
      Text(
        L10n.text(
          "Reads one bounded USB registry snapshot only after you ask. Model-level numeric identifiers remain on this page for this session."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)

      statusLabel

      HStack(spacing: 10) {
        let startLabel = L10n.text(
          isDemoMode ? "Load Demo USB Tree" : "Read Current USB Tree"
        )
        Button(startLabel) { model.start() }
          .disabled(!model.canStart)
          .accessibilityLabel(Text(startLabel))
          .accessibilityIdentifier("usb-inventory-start")

        if model.isAwaitingResult {
          ProgressView()
            .controlSize(.small)
        } else if model.isOperationInFlight {
          Text(L10n.text("The registry read may still be finishing."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let result = model.result {
        resultView(result)
      }

      Text(
        L10n.text(
          "No serial numbers, names, locations, registry paths, descriptors, device opens, persistence, history, diagnostics values, or export."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      Text(
        L10n.text(
          "Connection speed is a reported link category, not a maximum capability or measured throughput."
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
      L10n.text("Idle — the USB tree has not been read this session.")
    case .reading:
      L10n.text("Reading the current bounded USB tree…")
    case .ready:
      L10n.text("USB tree available on this page for this session.")
    case .limited:
      L10n.text("USB tree available with malformed or detached records omitted.")
    case .empty:
      L10n.text("The registry snapshot contained no USB devices.")
    case .timedOutWaiting:
      L10n.text("Stopped waiting after two seconds; any late result will be discarded.")
    case .failed(let failure):
      failureText(failure)
    }
  }

  private var statusSymbol: String {
    switch model.status {
    case .idle: "pause.circle"
    case .reading: "point.3.connected.trianglepath.dotted"
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

  private func failureText(_ failure: USBInventoryFailure) -> String {
    switch failure {
    case .operationNotPermitted:
      L10n.text("macOS did not permit this USB registry read.")
    case .unsupported:
      L10n.text("This Mac does not expose the required public USB registry service.")
    case .enumerationUnavailable:
      L10n.text("USB registry enumeration is temporarily unavailable.")
    case .safetyLimitReached:
      L10n.text("The USB tree exceeded its safety limit and was not shown.")
    case .invalidTopology:
      L10n.text("The USB topology changed or was invalid while being read.")
    case .failed:
      L10n.text("The USB registry read failed without exposing system error text.")
    }
  }

  private func resultView(_ result: USBInventorySnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        L10n.format(
          "%lld devices • %lld interfaces in this snapshot",
          Int64(result.reportedDeviceCount),
          Int64(result.reportedInterfaceCount)
        )
      )
      .font(.headline.monospacedDigit())

      if result.isLimited {
        Text(
          L10n.format(
            "%lld detached interfaces • %lld malformed fields omitted",
            Int64(result.discardedInterfaceCount),
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

  private func deviceView(_ device: USBInventoryDevice) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text(L10n.format("USB Device %lld", Int64(device.ordinal)))
          .font(.headline)
        Spacer()
        if let classCode = device.deviceClass,
          let className = USBInventoryClassName.displayName(
            for: classCode,
            deviceContext: true
          )
        {
          Text(L10n.text(className))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
      }

      Text(
        device.parentOrdinal.map {
          L10n.format("Child of USB Device %lld", Int64($0))
        } ?? L10n.text("Top-level USB device")
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      USBInventoryFactRow(
        label: L10n.text("Vendor ID / Product ID"),
        value: "\(hex16(device.vendorID)) / \(hex16(device.productID))"
      )
      USBInventoryFactRow(
        label: L10n.text("Device release number (bcdDevice)"),
        value: hex16(device.deviceReleaseNumber)
      )
      USBInventoryFactRow(
        label: L10n.text("Device class / subclass / protocol"),
        value: classTriple(device.deviceClass, device.deviceSubClass, device.deviceProtocol)
      )
      USBInventoryFactRow(
        label: L10n.text("Current configuration value"),
        value: decimal(device.currentConfiguration)
      )
      USBInventoryFactRow(
        label: L10n.text("Connection speed"),
        value: device.connectionSpeed.map { L10n.text($0.displayName) }
          ?? L10n.text("Not reported")
      )

      ForEach(device.interfaces) { interface in
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(
              L10n.format(
                "Interface %lld.%lld",
                Int64(device.ordinal),
                Int64(interface.ordinal)
              )
            )
            .font(.callout.weight(.semibold))
            if let classCode = interface.interfaceClass,
              let className = USBInventoryClassName.displayName(
                for: classCode,
                deviceContext: false
              )
            {
              Text(L10n.text(className))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          USBInventoryFactRow(
            label: L10n.text("Interface number"),
            value: decimal(interface.interfaceNumber)
          )
          USBInventoryFactRow(
            label: L10n.text("Interface class / subclass / protocol"),
            value: classTriple(
              interface.interfaceClass,
              interface.interfaceSubClass,
              interface.interfaceProtocol
            )
          )
          USBInventoryFactRow(
            label: L10n.text("Alternate setting"),
            value: decimal(interface.alternateSetting)
          )
        }
        .padding(.leading, 12)
        .padding(.vertical, 7)
        .overlay(alignment: .leading) {
          Rectangle().fill(.quaternary).frame(width: 2)
        }
      }
    }
    .padding(12)
    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    .padding(.leading, CGFloat(min(device.depth, 6)) * 14)
  }

  private func hex16(_ value: UInt16?) -> String {
    value.map { String(format: "0x%04X", $0) } ?? L10n.text("Not reported")
  }

  private func decimal(_ value: UInt8?) -> String {
    value.map(String.init) ?? L10n.text("Not reported")
  }

  private func classTriple(_ first: UInt8?, _ second: UInt8?, _ third: UInt8?) -> String {
    [first, second, third]
      .map { $0.map { String(format: "0x%02X", $0) } ?? L10n.text("Not reported") }
      .joined(separator: " / ")
  }
}

private struct USBInventoryFactRow: View {
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
