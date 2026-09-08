import AppKit
import Combine
import SensorCore
import SwiftUI

enum DisplayRulerStatus: Equatable {
  case locating
  case ready
  case calibrated
  case invalidated
  case invalidInput
  case unavailable
}

@MainActor
final class DisplayRulerModel: ObservableObject {
  @Published var referenceMillimeters = 50.0
  @Published var requestedRenderedPoints = 180.0
  @Published private(set) var context: DisplayCalibrationContext?
  @Published private(set) var measurement: DisplayCalibrationMeasurement?
  @Published private(set) var systemEstimate: DisplayCalibrationSystemEstimate?
  @Published private(set) var status = DisplayRulerStatus.locating

  private let session: DisplayCalibrationSession

  init(session: DisplayCalibrationSession = DisplayCalibrationSession()) {
    self.session = session
  }

  func refresh(for screen: NSScreen?) {
    guard let screen else {
      updateCurrentContext(nil)
      return
    }

    guard session.refreshFromSystem() else {
      updateCurrentContext(nil)
      return
    }

    updateCurrentContext(session.context(for: screen))
  }

  func updateCurrentContext(_ newContext: DisplayCalibrationContext?) {
    let previousContext = context
    let previousMeasurement = measurement
    let previousCalibrationWasInvalidated =
      previousMeasurement != nil
      && previousContext.map { session.calibration(for: $0) == nil } == true

    context = newContext
    guard let newContext else {
      measurement = nil
      systemEstimate = nil
      status = .unavailable
      return
    }

    measurement = session.calibration(for: newContext)
    systemEstimate = session.systemEstimate(for: newContext)
    if measurement != nil {
      status = .calibrated
    } else if previousCalibrationWasInvalidated {
      status = .invalidated
    } else {
      status = .ready
    }
  }

  func calibrate(renderedPoints: Double) {
    guard let context else {
      measurement = nil
      status = .unavailable
      return
    }

    guard session.context(forSlotIndex: context.slotIndex) == context else {
      updateCurrentContext(session.context(forSlotIndex: context.slotIndex))
      status = .invalidated
      return
    }

    requestedRenderedPoints = renderedPoints
    guard
      let result = session.calibrateHorizontal(
        context: context,
        referenceMillimeters: referenceMillimeters,
        renderedPoints: renderedPoints
      )
    else {
      measurement = session.calibration(for: context)
      status = .invalidInput
      return
    }

    measurement = result
    status = .calibrated
  }

  func clearCalibration() {
    guard let context else { return }
    guard session.clearCalibration(for: context) else {
      updateCurrentContext(session.context(forSlotIndex: context.slotIndex))
      status = .invalidated
      return
    }

    measurement = nil
    status = .ready
  }
}

struct DisplayRulerLayout {
  static let minimumRenderedPoints = 20.0
  static let maximumRenderedPoints = 600.0
  static let horizontalSafetyInset = 16.0

  static func maximumRenderedPoints(availableWidth: Double) -> Double {
    guard availableWidth.isFinite else { return minimumRenderedPoints }
    return min(
      maximumRenderedPoints,
      max(minimumRenderedPoints, availableWidth - horizontalSafetyInset)
    )
  }

  static func renderedPoints(requested: Double, availableWidth: Double) -> Double {
    let maximum = maximumRenderedPoints(availableWidth: availableWidth)
    guard requested.isFinite else { return minimumRenderedPoints }
    return min(maximum, max(minimumRenderedPoints, requested))
  }
}

struct DisplayRulerPanel: View {
  @ObservedObject var model: DisplayRulerModel
  let isDemoMode: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(L10n.text("Physical Display Ruler"), systemImage: "ruler")
        .font(.title3.weight(.semibold))
      Text(
        L10n.text(
          "Match the on-screen line to a real ruler to calibrate only the current horizontal axis."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)

      if isDemoMode {
        Label(
          L10n.text(
            "Display ruler is unavailable in Demo mode because it must use the real screen geometry."
          ),
          systemImage: "testtube.2"
        )
        .foregroundStyle(.orange)
      } else {
        rulerControls
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .background {
      if !isDemoMode {
        CurrentWindowScreenObserver { screen in
          model.refresh(for: screen)
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
      }
    }
  }

  @ViewBuilder
  private var rulerControls: some View {
    statusLabel

    if let context = model.context {
      Text(
        L10n.format(
          "Session display %lld • %lld × %lld points • %lld × %lld pixels",
          Int64(context.slotIndex),
          Int64(context.mode.pointWidth),
          Int64(context.mode.pointHeight),
          Int64(context.mode.pixelWidth),
          Int64(context.mode.pixelHeight)
        )
      )
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(L10n.text("Reference length"))
        TextField(
          L10n.text("Reference length"),
          value: $model.referenceMillimeters,
          format: .number.precision(.fractionLength(0...2))
        )
        .frame(width: 90)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(L10n.text("Reference length in millimeters"))
        Text("mm").foregroundStyle(.secondary)
      }

      GeometryReader { geometry in
        let availableWidth = Double(geometry.size.width)
        let maximum = DisplayRulerLayout.maximumRenderedPoints(
          availableWidth: availableWidth
        )
        let renderedPoints = DisplayRulerLayout.renderedPoints(
          requested: model.requestedRenderedPoints,
          availableWidth: availableWidth
        )
        VStack(alignment: .leading, spacing: 10) {
          DisplayRulerMark(renderedPoints: renderedPoints)
          HStack(spacing: 10) {
            if maximum > DisplayRulerLayout.minimumRenderedPoints {
              Slider(
                value: Binding(
                  get: { renderedPoints },
                  set: { model.requestedRenderedPoints = $0 }
                ),
                in: DisplayRulerLayout.minimumRenderedPoints...maximum,
                step: 0.5
              ) {
                Text(L10n.text("Rendered ruler width"))
              }
              .accessibilityValue(
                L10n.format(
                  "%@ points",
                  formatted(renderedPoints, fractionDigits: 1)
                )
              )
            } else {
              Spacer()
            }
            Text(
              L10n.format(
                "%@ points",
                formatted(renderedPoints, fractionDigits: 1)
              )
            )
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 92, alignment: .trailing)
          }
          HStack {
            Button(L10n.text("Calibrate This Display")) {
              model.calibrate(renderedPoints: renderedPoints)
            }
            .keyboardShortcut(.return, modifiers: [])
            if model.measurement != nil {
              Button(L10n.text("Clear Display Calibration")) {
                model.clearCalibration()
              }
            }
          }
        }
      }
      .frame(height: 112)

      comparisonMetrics

      Text(
        L10n.text(
          "User-referenced, not certified metrology. Only the horizontal axis is calibrated; vertical size and diagonal are not inferred."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      Text(
        L10n.text(
          "Calibration exists only for this app session and this display mode."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var comparisonMetrics: some View {
    HStack(spacing: 8) {
      DisplayRulerMetric(
        label: L10n.text("System estimated horizontal span"),
        value: model.systemEstimate.map {
          "\(formatted($0.horizontalSpanMillimeters, fractionDigits: 1)) mm"
        } ?? L10n.text("Unavailable")
      )
      DisplayRulerMetric(
        label: L10n.text("System estimated PPI"),
        value: model.systemEstimate.map {
          "\(formatted($0.horizontalPixelsPerInch, fractionDigits: 1)) ppi"
        } ?? L10n.text("Unavailable")
      )
    }

    if let measurement = model.measurement {
      HStack(spacing: 8) {
        DisplayRulerMetric(
          label: L10n.text("User calibrated horizontal span"),
          value: "\(formatted(measurement.physicalWidthMillimeters, fractionDigits: 1)) mm"
        )
        DisplayRulerMetric(
          label: L10n.text("User calibrated horizontal PPI"),
          value: "\(formatted(measurement.horizontalPixelsPerInch, fractionDigits: 1)) ppi"
        )
        DisplayRulerMetric(
          label: L10n.text("Millimeters per point"),
          value: formatted(measurement.millimetersPerPoint, fractionDigits: 4)
        )
      }
    }
  }

  @ViewBuilder
  private var statusLabel: some View {
    let content = statusContent
    Label(content.text, systemImage: content.symbol)
      .font(.caption.weight(.medium))
      .foregroundStyle(content.color)
      .accessibilityIdentifier("display-ruler-status")
  }

  private var statusContent: (text: String, symbol: String, color: Color) {
    switch model.status {
    case .locating:
      (
        L10n.text("Locating the display containing this window…"),
        "display",
        .secondary
      )
    case .ready:
      (
        L10n.text("Current display ready for a session-only calibration."),
        "checkmark.circle",
        .green
      )
    case .calibrated:
      (
        L10n.text("User-referenced horizontal calibration is active for this display mode."),
        "checkmark.seal",
        .green
      )
    case .invalidated:
      (
        L10n.text("Display configuration changed. The previous calibration was discarded."),
        "exclamationmark.triangle",
        .orange
      )
    case .invalidInput:
      (
        L10n.text(
          "Enter 10–2000 mm and choose a line width that produces a plausible 10–2000 PPI result."
        ),
        "exclamationmark.triangle",
        .orange
      )
    case .unavailable:
      (
        L10n.text("The current window could not be bound to an active display."),
        "xmark.circle",
        .orange
      )
    }
  }

  private func formatted(_ value: Double, fractionDigits: Int) -> String {
    value.formatted(
      .number.precision(.fractionLength(0...fractionDigits))
    )
  }
}

private struct DisplayRulerMark: View {
  let renderedPoints: Double

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color.primary)
        .frame(width: renderedPoints, height: 2)
      HStack {
        Rectangle().fill(Color.primary).frame(width: 2, height: 22)
        Spacer()
        Rectangle().fill(Color.primary).frame(width: 2, height: 22)
      }
      .frame(width: renderedPoints)
    }
    .frame(maxWidth: .infinity, minHeight: 26)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      L10n.format(
        "On-screen reference line, %@ points",
        renderedPoints.formatted(.number.precision(.fractionLength(0...1)))
      )
    )
  }
}

private struct DisplayRulerMetric: View {
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

private struct CurrentWindowScreenObserver: NSViewRepresentable {
  let onScreenChange: (NSScreen?) -> Void

  func makeNSView(context: Context) -> WindowScreenTrackingView {
    let view = WindowScreenTrackingView()
    view.onScreenChange = onScreenChange
    return view
  }

  func updateNSView(_ nsView: WindowScreenTrackingView, context: Context) {
    nsView.onScreenChange = onScreenChange
  }

  static func dismantleNSView(_ nsView: WindowScreenTrackingView, coordinator: ()) {
    nsView.stopObserving()
  }
}

private final class WindowScreenTrackingView: NSView {
  var onScreenChange: ((NSScreen?) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    startObserving()
    reportCurrentScreen()
  }

  func stopObserving() {
    NotificationCenter.default.removeObserver(self)
  }

  private func startObserving() {
    stopObserving()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowScreenChanged),
      name: NSWindow.didChangeScreenNotification,
      object: window
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenParametersChanged),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  @objc private func windowScreenChanged() {
    reportCurrentScreen()
  }

  @objc private func screenParametersChanged() {
    reportCurrentScreen()
  }

  private func reportCurrentScreen() {
    onScreenChange?(window?.screen)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
