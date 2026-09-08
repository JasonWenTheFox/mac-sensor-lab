import Combine
import Foundation
import SensorCore
import SwiftUI

enum WiFiChannelScanStatus: Equatable {
  case idle
  case scanning
  case ready
  case empty
  case stoppedWaiting
  case timedOutWaiting
  case failed(WiFiChannelScanFailure)
}

@MainActor
final class WiFiChannelScanModel: ObservableObject {
  typealias ScanOperation = @Sendable () async -> WiFiChannelScanOutcome

  static let defaultTimeout: Duration = .seconds(20)
  static let defaultCooldown: Duration = .seconds(10)

  @Published private(set) var status = WiFiChannelScanStatus.idle
  @Published private(set) var result: WiFiChannelScanResult?
  @Published private(set) var isAwaitingResult = false
  @Published private(set) var isOperationInFlight = false
  @Published private(set) var isCoolingDown = false

  private let operation: ScanOperation
  private let timeout: Duration
  private let cooldown: Duration
  private var nextOperationID: UInt64 = 1
  private var activeOperationID: UInt64?
  private var presentedOperationID: UInt64?
  private var scanTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var cooldownTask: Task<Void, Never>?

  var canStart: Bool {
    !isOperationInFlight && !isCoolingDown
  }

  init(
    isDemoMode: Bool = false,
    timeout: Duration = defaultTimeout,
    cooldown: Duration = defaultCooldown,
    operation: ScanOperation? = nil
  ) {
    self.timeout = timeout
    self.cooldown = cooldown
    self.operation = operation ?? (isDemoMode ? Self.demoScan : Self.liveScan)
  }

  func start() {
    guard canStart, nextOperationID < .max else { return }

    let operationID = nextOperationID
    nextOperationID += 1
    activeOperationID = operationID
    presentedOperationID = operationID
    result = nil
    status = .scanning
    isAwaitingResult = true
    isOperationInFlight = true

    let operation = self.operation
    scanTask = Task { [weak self] in
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

  func stopWaiting() {
    guard isAwaitingResult else { return }
    presentedOperationID = nil
    isAwaitingResult = false
    timeoutTask?.cancel()
    timeoutTask = nil
    status = .stoppedWaiting
  }

  func leaveExperiment() {
    presentedOperationID = nil
    isAwaitingResult = false
    timeoutTask?.cancel()
    timeoutTask = nil
    result = nil
    status = .idle
  }

  private func operationFinished(_ operationID: UInt64, outcome: WiFiChannelScanOutcome) {
    guard activeOperationID == operationID else { return }

    activeOperationID = nil
    isOperationInFlight = false
    scanTask = nil
    timeoutTask?.cancel()
    timeoutTask = nil

    if presentedOperationID == operationID, isAwaitingResult {
      presentedOperationID = nil
      isAwaitingResult = false
      switch outcome {
      case .success(let scanResult):
        result = scanResult
        status = scanResult.channels.isEmpty ? .empty : .ready
      case .failure(let failure):
        result = nil
        status = .failed(failure)
      }
    }

    beginCooldown()
  }

  private func waitingTimedOut(_ operationID: UInt64) {
    guard activeOperationID == operationID, presentedOperationID == operationID else { return }
    presentedOperationID = nil
    isAwaitingResult = false
    timeoutTask = nil
    result = nil
    status = .timedOutWaiting
  }

  private func beginCooldown() {
    isCoolingDown = true
    cooldownTask?.cancel()
    let cooldown = self.cooldown
    cooldownTask = Task { [weak self] in
      do {
        try await Task.sleep(for: cooldown)
      } catch {
        return
      }
      guard let self else { return }
      self.isCoolingDown = false
      self.cooldownTask = nil
    }
  }

  private static let liveScan: ScanOperation = {
    await WiFiChannelScanner.scan()
  }

  private static let demoScan: ScanOperation = {
    try? await Task.sleep(for: .milliseconds(350))
    return .success(
      WiFiChannelScanResult(
        completedAt: Date(),
        reportedRecordCount: 7,
        acceptedRecordCount: 7,
        discardedRecordCount: 0,
        truncatedRecordCount: 0,
        channels: [
          WiFiChannelScanSummary(
            band: .band2GHz,
            channelNumber: 1,
            reportedRecordCount: 2,
            strongestRSSIDBm: -42,
            averageRSSIDBm: -57.5,
            reportedChannelWidthsMHz: [20]
          ),
          WiFiChannelScanSummary(
            band: .band2GHz,
            channelNumber: 6,
            reportedRecordCount: 3,
            strongestRSSIDBm: -55,
            averageRSSIDBm: -68,
            reportedChannelWidthsMHz: [20, 40]
          ),
          WiFiChannelScanSummary(
            band: .band5GHz,
            channelNumber: 44,
            reportedRecordCount: 1,
            strongestRSSIDBm: -63,
            averageRSSIDBm: -63,
            reportedChannelWidthsMHz: [80]
          ),
          WiFiChannelScanSummary(
            band: .band6GHz,
            channelNumber: 69,
            reportedRecordCount: 1,
            strongestRSSIDBm: -72,
            averageRSSIDBm: -72,
            reportedChannelWidthsMHz: [160]
          ),
        ]
      )
    )
  }
}

struct WiFiChannelScanPanel: View {
  @ObservedObject var model: WiFiChannelScanModel
  let isDemoMode: Bool
  @State private var showsScanConfirmation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(L10n.text("Nearby Wi-Fi Channels"), systemImage: "wifi.exclamationmark")
        .font(.title3.weight(.semibold))
      Text(
        L10n.text(
          "Runs one user-started CoreWLAN scan and immediately reduces the result to radio-channel summaries."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)

      statusLabel

      HStack(spacing: 10) {
        if model.isAwaitingResult {
          Button {
            model.stopWaiting()
          } label: {
            Text(L10n.text("Stop Waiting"))
          }
          .accessibilityLabel(Text(L10n.text("Stop Waiting")))
          .accessibilityIdentifier("wifi-channel-scan-stop-waiting")
        } else {
          let startLabel = L10n.text(isDemoMode ? "Run Demo Scan" : "Scan Nearby Channels")
          Button {
            showsScanConfirmation = true
          } label: {
            Text(startLabel)
          }
          .disabled(!model.canStart)
          .accessibilityLabel(Text(startLabel))
          .accessibilityIdentifier("wifi-channel-scan-start")
        }

        if model.isOperationInFlight, !model.isAwaitingResult {
          Text(L10n.text("The system scan may still be finishing."))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if model.isCoolingDown {
          Text(L10n.text("A short cooldown prevents repeated scans."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let result = model.result {
        resultView(result)
      }

      Text(
        L10n.text(
          "No network name, access-point address, country code, interface identity, information elements, location, persistence, or export."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      Text(
        L10n.text(
          "Reported records and RSSI are a momentary view of advertisements, not airtime use, interference, throughput, or a complete congestion measurement."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .confirmationDialog(
      L10n.text(isDemoMode ? "Run one demo scan?" : "Run one nearby-channel scan?"),
      isPresented: $showsScanConfirmation,
      titleVisibility: .visible
    ) {
      Button(L10n.text(isDemoMode ? "Run Demo Scan" : "Start One Scan")) {
        model.start()
      }
      Button(L10n.text("Cancel"), role: .cancel) {}
    } message: {
      Text(
        L10n.text(
          isDemoMode
            ? "Demo mode uses fixed, non-identifying fixture data and does not access Wi-Fi hardware."
            : "Scanning briefly uses the Wi-Fi radio and can momentarily affect connectivity. Results stay in this panel and omit network identities."
        )
      )
    }
    .onDisappear { model.leaveExperiment() }
  }

  private var statusLabel: some View {
    Label(statusText, systemImage: statusSymbol)
      .font(.callout.weight(.medium))
      .foregroundStyle(statusColor)
  }

  private var statusText: String {
    switch model.status {
    case .idle:
      L10n.text("Idle — no nearby scan has run this session.")
    case .scanning:
      L10n.text("Waiting for the system Wi-Fi scan…")
    case .ready:
      L10n.text("Channel snapshot available for this session.")
    case .empty:
      L10n.text("The scan completed without usable channel records.")
    case .stoppedWaiting:
      L10n.text("Stopped waiting; any late system result will be discarded.")
    case .timedOutWaiting:
      L10n.text("Stopped waiting after 20 seconds; any late result will be discarded.")
    case .failed(let failure):
      failureText(failure)
    }
  }

  private var statusSymbol: String {
    switch model.status {
    case .idle: "pause.circle"
    case .scanning: "antenna.radiowaves.left.and.right"
    case .ready: "checkmark.circle"
    case .empty: "minus.circle"
    case .stoppedWaiting, .timedOutWaiting, .failed: "exclamationmark.triangle"
    }
  }

  private var statusColor: Color {
    switch model.status {
    case .ready: .green
    case .scanning: .blue
    case .idle, .empty: .secondary
    case .stoppedWaiting, .timedOutWaiting, .failed: .orange
    }
  }

  private func failureText(_ failure: WiFiChannelScanFailure) -> String {
    switch failure {
    case .interfaceUnavailable:
      L10n.text("A Wi-Fi interface was not reported.")
    case .wifiOffOrUnavailable:
      L10n.text("Wi-Fi is off or its power state is unavailable.")
    case .serviceInactiveOrUnavailable:
      L10n.text("The Wi-Fi network service is inactive or unavailable.")
    case .operationNotPermitted:
      L10n.text("macOS did not permit this Wi-Fi scan.")
    case .systemTimeout:
      L10n.text("CoreWLAN reported that the scan timed out.")
    case .unsupported:
      L10n.text("This Wi-Fi scan is not supported on the current system.")
    case .failed:
      L10n.text("The Wi-Fi scan failed without exposing system error details.")
    }
  }

  private func resultView(_ result: WiFiChannelScanResult) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        L10n.format(
          "%lld accepted records across %lld channels",
          Int64(result.acceptedRecordCount),
          Int64(result.channels.count)
        )
      )
      .font(.headline)

      ScrollView {
        LazyVStack(spacing: 6) {
          ForEach(result.channels) { channel in
            channelRow(channel)
          }
        }
      }
      .frame(maxHeight: 280)

      if result.discardedRecordCount > 0 || result.truncatedRecordCount > 0 {
        Text(
          L10n.format(
            "%lld malformed records discarded • %lld records omitted by the safety limit",
            Int64(result.discardedRecordCount),
            Int64(result.truncatedRecordCount)
          )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
  }

  private func channelRow(_ channel: WiFiChannelScanSummary) -> some View {
    HStack(spacing: 10) {
      Text(channel.band.displayName)
        .frame(width: 58, alignment: .leading)
      Text(L10n.format("Channel %lld", Int64(channel.channelNumber)))
        .frame(width: 92, alignment: .leading)
      Text(L10n.format("%lld records", Int64(channel.reportedRecordCount)))
        .frame(width: 82, alignment: .leading)
      Spacer(minLength: 4)
      if let strongest = channel.strongestRSSIDBm {
        Text("\(strongest) dBm")
          .monospacedDigit()
      } else {
        Text(L10n.text("RSSI unavailable"))
          .foregroundStyle(.secondary)
      }
      if !channel.reportedChannelWidthsMHz.isEmpty {
        Text("\(channel.reportedChannelWidthsMHz.map(String.init).joined(separator: "/")) MHz")
          .foregroundStyle(.secondary)
      }
    }
    .font(.caption)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }
}
