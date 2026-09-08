import AppKit
import Charts
import Combine
import Foundation
import SwiftUI

struct PressureLabEventInput: Equatable, Sendable {
  let timestamp: TimeInterval
  let normalizedPressure: Double
  let stage: Int
  let stageTransition: Double

  init?(
    timestamp: TimeInterval,
    normalizedPressure: Double,
    stage: Int,
    stageTransition: Double
  ) {
    guard timestamp.isFinite,
      timestamp >= 0,
      normalizedPressure.isFinite,
      (0...1).contains(normalizedPressure),
      (0...2).contains(stage),
      stageTransition.isFinite,
      (-1...1).contains(stageTransition)
    else {
      return nil
    }

    self.timestamp = timestamp
    self.normalizedPressure = normalizedPressure
    self.stage = stage
    self.stageTransition = stageTransition
  }
}

struct PressureLabSample: Equatable, Identifiable, Sendable {
  let id: UInt64
  let segmentID: UInt64
  let elapsedSeconds: TimeInterval
  let normalizedPressure: Double
  let stage: Int
  let stageTransition: Double
}

enum PressureLabStatus: Equatable {
  case idle
  case waiting
  case receiving
  case unsupportedInput
  case stopped
}

@MainActor
final class PressureLabModel: ObservableObject {
  static let maximumSampleCount = 240

  @Published private(set) var isCapturing = false
  @Published private(set) var samples: [PressureLabSample] = []
  @Published private(set) var forceClickTransitionCount = 0
  @Published private(set) var inputSupportsPressure: Bool?
  @Published private(set) var status = PressureLabStatus.idle

  private var startedAt: TimeInterval?
  private var lastEventTimestamp: TimeInterval?
  private var lastStage: Int?
  private var nextSequence: UInt64 = 1
  private var currentSegment: UInt64 = 0

  var latestSample: PressureLabSample? { samples.last }

  var peakNormalizedPressureForCurrentStage: Double? {
    guard let segmentID = latestSample?.segmentID else { return nil }
    return samples.lazy
      .filter { $0.segmentID == segmentID }
      .map(\.normalizedPressure)
      .max()
  }

  func start(at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    guard timestamp.isFinite, timestamp >= 0 else {
      leaveExperiment()
      return
    }

    clearSessionState()
    startedAt = timestamp
    isCapturing = true
    status = .waiting
  }

  func stop() {
    guard isCapturing else { return }
    isCapturing = false
    status = .stopped
  }

  func clear() {
    let wasCapturing = isCapturing
    clearSessionState()
    isCapturing = wasCapturing
    if wasCapturing {
      startedAt = ProcessInfo.processInfo.systemUptime
      status = .waiting
    } else {
      status = .idle
    }
  }

  func leaveExperiment() {
    isCapturing = false
    clearSessionState()
    status = .idle
  }

  func observeInputCapability(_ supportsPressure: Bool) {
    guard isCapturing else { return }
    inputSupportsPressure = supportsPressure
    guard samples.isEmpty else { return }
    status = supportsPressure ? .waiting : .unsupportedInput
  }

  @discardableResult
  func record(_ input: PressureLabEventInput) -> Bool {
    guard isCapturing,
      let startedAt,
      input.timestamp >= startedAt,
      lastEventTimestamp.map({ input.timestamp >= $0 }) ?? true,
      nextSequence < .max,
      currentSegment < .max
    else {
      return false
    }

    if lastStage != input.stage {
      currentSegment += 1
    }
    if input.stage == 2, lastStage != 2, forceClickTransitionCount < .max {
      forceClickTransitionCount += 1
    }

    let sample = PressureLabSample(
      id: nextSequence,
      segmentID: currentSegment,
      elapsedSeconds: input.timestamp - startedAt,
      normalizedPressure: input.normalizedPressure,
      stage: input.stage,
      stageTransition: input.stageTransition
    )
    guard sample.elapsedSeconds.isFinite, sample.elapsedSeconds >= 0 else {
      return false
    }

    nextSequence += 1
    lastEventTimestamp = input.timestamp
    lastStage = input.stage
    samples.append(sample)
    if samples.count > Self.maximumSampleCount {
      samples.removeFirst(samples.count - Self.maximumSampleCount)
    }
    inputSupportsPressure = true
    status = .receiving
    return true
  }

  private func clearSessionState() {
    samples.removeAll(keepingCapacity: true)
    forceClickTransitionCount = 0
    inputSupportsPressure = nil
    startedAt = nil
    lastEventTimestamp = nil
    lastStage = nil
    nextSequence = 1
    currentSegment = 0
  }
}

struct PressureLabPanel: View {
  @ObservedObject var model: PressureLabModel
  let isDemoMode: Bool
  let forceTouchPresence: Bool?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(L10n.text("Force Touch Pressure Lab"), systemImage: "hand.point.up.left")
        .font(.title3.weight(.semibold))
      Text(
        L10n.text(
          "Reads public AppKit pressure events only inside the interaction area below."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)

      if isDemoMode {
        Label(
          L10n.text(
            "Pressure Lab is unavailable in Demo mode because it requires live local input."
          ),
          systemImage: "testtube.2"
        )
        .foregroundStyle(.orange)
      } else {
        controls
      }

      Text(
        L10n.text(
          "Pressure is normalized from 0 to 1 within each stage. It is not force, weight, grams, or a calibrated physical measurement."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      Text(
        L10n.text(
          "No global input monitoring, raw contacts, device identifiers, persistence, or export."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .onDisappear { model.leaveExperiment() }
  }

  @ViewBuilder
  private var controls: some View {
    statusLabel

    HStack {
      if model.isCapturing {
        Button(L10n.text("Stop Pressure Capture")) { model.stop() }
          .buttonStyle(.borderedProminent)
      } else {
        Button(L10n.text("Start Pressure Capture")) { model.start() }
          .buttonStyle(.borderedProminent)
      }
      Button(L10n.text("Clear Pressure Samples")) { model.clear() }
        .disabled(model.samples.isEmpty)
    }

    if model.isCapturing {
      PressureCaptureSurface(
        isCapturing: true,
        accessibilityLabel: L10n.text("Force Touch pressure interaction area"),
        onInputCapability: model.observeInputCapability,
        onEvent: { timestamp, pressure, stage, transition in
          guard
            let input = PressureLabEventInput(
              timestamp: timestamp,
              normalizedPressure: pressure,
              stage: stage,
              stageTransition: transition
            )
          else { return }
          model.record(input)
        }
      )
      .frame(height: 118)
      .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        VStack(spacing: 5) {
          Image(systemName: "hand.point.up.left.fill")
            .font(.title2)
          Text(L10n.text("Click and press here with a Force Touch trackpad"))
            .font(.callout.weight(.medium))
          Text(L10n.text("Keep the pointer inside this area during the gesture."))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .allowsHitTesting(false)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(
            Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [6])
          )
          .allowsHitTesting(false)
      }
    }

    pressureMetrics

    if model.samples.count >= 2 {
      Chart(model.samples) { sample in
        LineMark(
          x: .value("Elapsed time", sample.elapsedSeconds),
          y: .value("Normalized pressure", sample.normalizedPressure),
          series: .value("Stage segment", sample.segmentID)
        )
        .interpolationMethod(.linear)
        .foregroundStyle(sample.stage == 2 ? Color.orange : Color.accentColor)
      }
      .chartYScale(domain: 0...1)
      .chartXAxis(.hidden)
      .chartYAxis {
        AxisMarks(values: [0, 0.5, 1])
      }
      .frame(height: 110)
      .accessibilityLabel(
        L10n.format(
          "Normalized pressure trend with %lld samples",
          Int64(model.samples.count)
        )
      )
      Text(
        L10n.text(
          "The curve is split at every stage change; values from different stages are never added together."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  private var pressureMetrics: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
      PressureLabMetric(
        label: L10n.text("Normalized pressure"),
        value: model.latestSample.map {
          $0.normalizedPressure.formatted(.number.precision(.fractionLength(3)))
        } ?? "—"
      )
      PressureLabMetric(
        label: L10n.text("Stage"),
        value: model.latestSample.map { String($0.stage) } ?? "—"
      )
      PressureLabMetric(
        label: L10n.text("Stage transition"),
        value: model.latestSample.map {
          $0.stageTransition.formatted(
            .number.precision(.fractionLength(3)).sign(strategy: .always()))
        } ?? "—"
      )
      PressureLabMetric(
        label: L10n.text("Stage 2 entries"),
        value: String(model.forceClickTransitionCount)
      )
      PressureLabMetric(
        label: L10n.text("Retained samples"),
        value: String(model.samples.count)
      )
      PressureLabMetric(
        label: L10n.text("Peak in current stage"),
        value: model.peakNormalizedPressureForCurrentStage.map {
          $0.formatted(.number.precision(.fractionLength(3)))
        } ?? "—"
      )
    }
  }

  private var statusLabel: some View {
    let content = statusContent
    return Label(content.text, systemImage: content.symbol)
      .font(.caption.weight(.medium))
      .foregroundStyle(content.color)
      .accessibilityIdentifier("pressure-lab-status")
  }

  private var statusContent: (text: String, symbol: String, color: Color) {
    switch model.status {
    case .idle:
      if forceTouchPresence == true {
        (
          L10n.text("Force Touch service detected. Start a local capture when ready."),
          "hand.point.up.left",
          .secondary
        )
      } else if forceTouchPresence == false {
        (
          L10n.text(
            "Force Touch service not detected. Start a local capture to check the active input device."
          ),
          "exclamationmark.triangle",
          .orange
        )
      } else {
        (
          L10n.text("Start a local capture to check the current input device."),
          "hand.point.up.left",
          .secondary
        )
      }
    case .waiting:
      (
        L10n.text("Waiting for pressure events inside the interaction area."),
        "circle.dashed",
        .secondary
      )
    case .receiving:
      (
        L10n.text("Receiving view-local AppKit pressure events."),
        "checkmark.circle",
        .green
      )
    case .unsupportedInput:
      (
        L10n.text(
          "The last click did not advertise pressure events. Try the Force Touch trackpad."
        ),
        "exclamationmark.triangle",
        .orange
      )
    case .stopped:
      (
        L10n.text("Capture stopped. Samples remain only until cleared or this page is left."),
        "stop.circle",
        .secondary
      )
    }
  }
}

private struct PressureLabMetric: View {
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

private struct PressureCaptureSurface: NSViewRepresentable {
  let isCapturing: Bool
  let accessibilityLabel: String
  let onInputCapability: (Bool) -> Void
  let onEvent: (TimeInterval, Double, Int, Double) -> Void

  func makeNSView(context: Context) -> PressureCaptureNSView {
    let view = PressureCaptureNSView()
    configure(view)
    return view
  }

  func updateNSView(_ nsView: PressureCaptureNSView, context: Context) {
    configure(nsView)
  }

  static func dismantleNSView(_ nsView: PressureCaptureNSView, coordinator: ()) {
    nsView.setCaptureEnabled(false)
    nsView.onInputCapability = nil
    nsView.onEvent = nil
  }

  private func configure(_ view: PressureCaptureNSView) {
    view.onInputCapability = onInputCapability
    view.onEvent = onEvent
    view.setAccessibilityLabel(accessibilityLabel)
    view.setCaptureEnabled(isCapturing)
  }
}

private final class PressureCaptureNSView: NSView {
  var onInputCapability: ((Bool) -> Void)?
  var onEvent: ((TimeInterval, Double, Int, Double) -> Void)?
  private var captureEnabled = false

  override var acceptsFirstResponder: Bool { captureEnabled }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
  }

  func setCaptureEnabled(_ enabled: Bool) {
    guard captureEnabled != enabled else { return }
    captureEnabled = enabled
    pressureConfiguration =
      enabled
      ? NSPressureConfiguration(pressureBehavior: .primaryDeepClick)
      : nil
  }

  override func mouseDown(with event: NSEvent) {
    guard captureEnabled else {
      super.mouseDown(with: event)
      return
    }

    window?.makeFirstResponder(self)
    onInputCapability?(event.associatedEventsMask.contains(.pressure))
  }

  override func pressureChange(with event: NSEvent) {
    guard captureEnabled, event.type == .pressure else {
      super.pressureChange(with: event)
      return
    }

    onEvent?(
      event.timestamp,
      Double(event.pressure),
      event.stage,
      Double(event.stageTransition)
    )
  }
}
