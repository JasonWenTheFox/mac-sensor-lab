import Charts
import SensorCore
import SwiftUI

struct RootView: View {
  @ObservedObject var model: SensorDashboardModel

  var body: some View {
    NavigationSplitView {
      List(DashboardSection.allCases, selection: $model.selection) { section in
        Label(section.rawValue, systemImage: section.symbol)
          .tag(section)
      }
      .navigationTitle("Mac Sensor Lab")
      .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    } detail: {
      VStack(spacing: 0) {
        if model.isDemoMode {
          Label("Demo data — not live sensor readings", systemImage: "testtube.2")
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .foregroundStyle(.orange)
            .background(.orange.opacity(0.12))
        }
        Group {
          switch model.selection ?? .overview {
          case .overview:
            OverviewView(
              snapshots: model.snapshots,
              history: model.history,
              isDemoMode: model.isDemoMode
            )
          case .rawSensors:
            RawSensorsView(snapshots: model.snapshots)
          case .experiments:
            ExperimentsView(
              snapshots: model.snapshots,
              history: model.history,
              ambientLuxCalibration: model.ambientLuxCalibration,
              onSetAmbientCalibration: model.setAmbientLuxCalibration,
              onClearAmbientCalibration: model.clearAmbientLuxCalibration,
              onExportAmbientCalibration: model.exportAmbientLuxCalibration,
              onImportAmbientCalibration: model.importAmbientLuxCalibration
            )
          case .diagnostics:
            DiagnosticsView(
              snapshots: model.snapshots,
              samplingCadence: model.samplingCadence,
              isSamplingPaused: model.isSamplingPaused,
              isDemoMode: model.isDemoMode,
              lastRefreshDate: model.lastRefreshDate,
              recordingFileName: model.recordingFileName,
              recordingProgress: model.recordingProgress,
              message: model.lastActionMessage,
              onExportDiagnostics: model.exportDiagnostics
            )
          }
        }
      }
      .toolbar {
        ToolbarItemGroup {
          Menu {
            Picker("Refresh interval", selection: $model.samplingCadence) {
              ForEach(SamplingCadence.allCases) { cadence in
                Text(cadence.displayName).tag(cadence)
              }
            }
            Divider()
            Button(
              model.isSamplingPaused ? "Resume Automatic Sampling" : "Pause Automatic Sampling"
            ) {
              model.toggleSampling()
            }
            Button("Clear Chart History") { model.clearHistory() }
          } label: {
            Label(
              model.isSamplingPaused ? "Paused" : model.samplingCadence.shortLabel,
              systemImage: model.isSamplingPaused ? "pause.circle" : "timer")
          }
          .help("Sampling controls")

          if model.isRecording {
            Button {
              Task { await model.stopRecording() }
            } label: {
              Label("Stop Recording", systemImage: "record.circle.fill")
                .foregroundStyle(.red)
            }
            .help("Stop continuous CSV recording")
          }

          Menu {
            Button("JSON Snapshot") { model.export(.json) }
            Button("CSV Channels") { model.export(.csv) }
            Divider()
            if model.isRecording {
              Button("Stop Continuous Recording") {
                Task { await model.stopRecording() }
              }
            } else {
              Button("Start Continuous CSV Recording…") { model.startRecording() }
            }
          } label: {
            Label("Export", systemImage: "square.and.arrow.up")
          }
          Button {
            Task { await model.refresh() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .disabled(model.isRefreshing)
        }
      }
    }
  }
}

private struct OverviewView: View {
  let snapshots: [SensorSnapshot]
  let history: [String: [SensorHistoryPoint]]
  let isDemoMode: Bool
  private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text("Overview")
          .font(.largeTitle.bold())
        Text(
          isDemoMode
            ? "Deterministic fixture readings for screenshots and UI review."
            : "Live local readings, with source and confidence kept visible."
        )
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 12)

      LazyVGrid(columns: columns, spacing: 16) {
        ForEach(snapshots) { snapshot in
          SensorCard(snapshot: snapshot, history: history)
        }
      }
    }
    .padding(24)
    .navigationTitle("Overview")
  }
}

private struct SensorCard: View {
  let snapshot: SensorSnapshot
  let history: [String: [SensorHistoryPoint]]

  private var chartChannel: SensorChannel? {
    let liveChannelIDs = [
      "cpu_utilization", "gpu_device_utilization", "network_receive_rate", "disk_read_rate",
      "cpu_hotspot", "system_power", "charge", "angle", "ambient_intensity",
    ]
    return liveChannelIDs.lazy.compactMap { id in
      snapshot.channels.first(where: { $0.id == id && $0.value != nil })
    }.first
  }

  private var chartPoints: [SensorHistoryPoint] {
    guard let channel = chartChannel else { return [] }
    return history["\(snapshot.id)/\(channel.id)", default: []]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Text(snapshot.name)
            .font(.headline)
          Text(snapshot.summary)
            .font(.title3.weight(.semibold))
            .lineLimit(2)
        }
        Spacer()
        StatusPill(status: snapshot.status)
      }

      if snapshot.status == .loading {
        ProgressView()
          .controlSize(.small)
      } else {
        ForEach(snapshot.channels.prefix(4)) { channel in
          HStack(alignment: .firstTextBaseline) {
            Text(channel.label)
              .foregroundStyle(.secondary)
            Spacer()
            Text(channel.formattedValue)
              .monospacedDigit()
            if let unit = channel.unit, shouldDisplayUnit(unit, for: channel) {
              Text(unit).foregroundStyle(.secondary)
            }
          }
          .font(.callout)
        }
      }

      if let channel = chartChannel, chartPoints.count >= 2 {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(channel.label) • recent samples")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Chart(chartPoints) { point in
            LineMark(
              x: .value("Time", point.timestamp),
              y: .value(channel.label, point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor)
            AreaMark(
              x: .value("Time", point.timestamp),
              y: .value(channel.label, point.value)
            )
            .foregroundStyle(
              .linearGradient(
                colors: [Color.accentColor.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
              )
            )
          }
          .chartXAxis(.hidden)
          .chartYAxis(.hidden)
          .frame(height: 44)
        }
        .accessibilityLabel("\(channel.label) trend with \(chartPoints.count) samples")
      }

      Divider()
      HStack {
        Text(snapshot.source)
        Spacer()
        Text(snapshot.capability.displayName)
      }
      .font(.caption)
      .foregroundStyle(.tertiary)
    }
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.quaternary, lineWidth: 1)
    }
  }
}

private struct StatusPill: View {
  let status: SensorStatus

  private var color: Color {
    switch status {
    case .available: .green
    case .loading: .blue
    case .degraded: .orange
    case .permissionRequired: .yellow
    case .unavailable: .gray
    case .error: .red
    }
  }

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(status.displayName)
    }
    .font(.caption.weight(.medium))
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(color.opacity(0.12), in: Capsule())
  }
}

private struct RawSensorsView: View {
  let snapshots: [SensorSnapshot]
  @State private var query = ""

  private var filteredSnapshots: [SensorSnapshot] {
    SensorSnapshotSearch.filter(snapshots, query: query)
  }

  var body: some View {
    List {
      if filteredSnapshots.isEmpty {
        ContentUnavailableView(
          "No Sensors Found",
          systemImage: "magnifyingglass",
          description: Text("Try a provider, channel, source, status, or stable ID.")
        )
      }
      ForEach(filteredSnapshots) { snapshot in
        Section {
          ForEach(snapshot.channels) { channel in
            VStack(alignment: .leading, spacing: 5) {
              HStack(alignment: .firstTextBaseline) {
                Text(channel.label)
                Spacer()
                Text(channel.formattedValue).monospacedDigit()
                if let unit = channel.unit, shouldDisplayUnit(unit, for: channel) {
                  Text(unit).foregroundStyle(.secondary)
                }
              }
              HStack(spacing: 8) {
                Text(channel.id).monospaced()
                Text(channel.kind.displayName)
                if let note = channel.note { Text(note) }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
          }
          if snapshot.channels.isEmpty {
            Text(snapshot.summary).foregroundStyle(.secondary)
          }
          ForEach(snapshot.notes, id: \.self) { note in
            Label(note, systemImage: "info.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } header: {
          HStack {
            Text(snapshot.name)
            Spacer()
            StatusPill(status: snapshot.status)
          }
        } footer: {
          Text(
            "Updated \(snapshot.timestamp.formatted(date: .omitted, time: .standard)) • Source: \(snapshot.source) • \(snapshot.capability.displayName)"
          )
        }
      }
    }
    .navigationTitle("Raw Sensors")
    .searchable(text: $query, prompt: "Provider, channel, source, status, or ID")
  }
}

private func shouldDisplayUnit(_ unit: String, for channel: SensorChannel) -> Bool {
  guard unit != "bytes", unit != "bytes/s" else { return false }
  return !channel.formattedValue.contains(unit)
}

private struct ExperimentsView: View {
  let snapshots: [SensorSnapshot]
  let history: [String: [SensorHistoryPoint]]
  let ambientLuxCalibration: AmbientLuxCalibration?
  let onSetAmbientCalibration: (Double, Double) -> Void
  let onClearAmbientCalibration: () -> Void
  let onExportAmbientCalibration: () -> Void
  let onImportAmbientCalibration: () -> Void

  private struct Experiment {
    let name: String
    let symbol: String
    let providerID: String?
    let channelID: String?
    let description: String
  }

  private let experiments = [
    Experiment(
      name: "Level", symbol: "level", providerID: "motion.spu_live", channelID: "level_roll",
      description: "Uses gravity-derived roll and pitch when live acceleration is available"),
    Experiment(
      name: "Lid Protractor", symbol: "angle", providerID: "motion.lid_angle", channelID: "angle",
      description: "Uses the undocumented lid-angle sensor"),
    Experiment(
      name: "Trackpad Scale", symbol: "scalemass", providerID: "diagnostics.hardware_capabilities",
      channelID: "force_touch",
      description: "Requires a future raw Force Touch provider and calibration"),
    Experiment(
      name: "Vibration Recorder", symbol: "waveform.path", providerID: "motion.spu_live",
      channelID: "acceleration_magnitude",
      description: "Uses live acceleration history when macOS publishes reports"),
    Experiment(
      name: "Light Meter", symbol: "sun.max", providerID: "motion.spu_live",
      channelID: "ambient_intensity",
      description: "Shows raw light first; lux requires model-specific calibration"),
    Experiment(
      name: "Sound Lab", symbol: "waveform", providerID: nil, channelID: nil,
      description: "Microphone access will be opt-in"),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text("Experiments").font(.largeTitle.bold())
        Text("Derived tools unlock only when their data source is verified.")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
        ForEach(experiments, id: \.name) { experiment in
          let dependency = snapshots.first { $0.id == experiment.providerID }
          let isReady = isReady(experiment, snapshot: dependency)
          VStack(alignment: .leading, spacing: 12) {
            Image(systemName: experiment.symbol)
              .font(.system(size: 28))
              .foregroundStyle(Color.accentColor)
            Text(experiment.name).font(.headline)
            Text(experiment.description).font(.callout).foregroundStyle(.secondary)
            if isReady, let dependency {
              liveReading(for: experiment, snapshot: dependency)
            }
            Spacer()
            Text(sourceState(isReady: isReady, snapshot: dependency))
              .font(.caption.weight(.medium))
              .foregroundStyle(isReady && dependency?.status == .available ? .green : .orange)
          }
          .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
          .padding(18)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
      }
      .padding(.top, 18)
    }
    .padding(24)
    .navigationTitle("Experiments")
  }

  private func isReady(_ experiment: Experiment, snapshot: SensorSnapshot?) -> Bool {
    guard let snapshot, let channelID = experiment.channelID else { return false }
    let statusIsReady =
      snapshot.status == .available
      || (snapshot.id == "motion.spu_live" && snapshot.status == .degraded)
    guard statusIsReady else { return false }
    return snapshot.channels.contains { $0.id == channelID && $0.value != nil }
  }

  private func sourceState(isReady: Bool, snapshot: SensorSnapshot?) -> String {
    guard isReady else { return "Foundation ready • provider pending" }
    return snapshot?.status == .degraded ? "Recent data • source limited" : "Data source ready"
  }

  @ViewBuilder
  private func liveReading(for experiment: Experiment, snapshot: SensorSnapshot) -> some View {
    if let channelID = experiment.channelID,
      let channel = snapshot.channels.first(where: { $0.id == channelID && $0.value != nil })
    {
      let points = history["\(snapshot.id)/\(channelID)", default: []]
      HStack(alignment: .firstTextBaseline) {
        Text(channel.formattedValue)
          .font(.title2.bold())
          .monospacedDigit()
        if let unit = channel.unit, shouldDisplayUnit(unit, for: channel) {
          Text(unit).foregroundStyle(.secondary)
        }
        Spacer()
        Text(channel.kind.displayName)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if channelID == "angle", let value = channel.value {
        Gauge(value: min(max(value, 0), 180), in: 0...180) {
          Text("Lid angle")
        } currentValueLabel: {
          Text("0° — 180°").font(.caption2)
        }
        .gaugeStyle(.linearCapacity)
        LidReferencePanel(currentAngle: value)
      }

      if channelID == "level_roll",
        let pitch = snapshot.channels.first(where: { $0.id == "level_pitch" })
      {
        HStack {
          Label("Roll \(channel.formattedValue)°", systemImage: "arrow.left.and.right")
          Spacer()
          Label("Pitch \(pitch.formattedValue)°", systemImage: "arrow.up.and.down")
        }
        .font(.caption)
        .monospacedDigit()
      }

      if channelID == "ambient_intensity" {
        spectralBars(snapshot.channels.filter { $0.id.hasPrefix("ambient_spectral_") })
        if let rawValue = channel.value {
          AmbientLightInterpretationPanel(
            rawValue: rawValue,
            historyValues: points.map(\.value),
            calibration: ambientLuxCalibration,
            onSetCalibration: onSetAmbientCalibration,
            onClearCalibration: onClearAmbientCalibration,
            onExportCalibration: onExportAmbientCalibration,
            onImportCalibration: onImportAmbientCalibration
          )
        }
      }

      if points.count >= 2 {
        Chart(points) { point in
          LineMark(x: .value("Time", point.timestamp), y: .value(channel.label, point.value))
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 34)
        .accessibilityLabel("\(channel.label) experiment trend")
      }
    }
  }

  @ViewBuilder
  private func spectralBars(_ channels: [SensorChannel]) -> some View {
    if !channels.isEmpty {
      let maximum = max(channels.compactMap(\.value).max() ?? 0, 1)
      HStack(alignment: .bottom, spacing: 8) {
        ForEach(channels) { channel in
          VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3)
              .fill(Color.accentColor.gradient)
              .frame(height: max(4, (channel.value ?? 0) / maximum * 30))
            Text(channel.formattedValue)
              .font(.system(size: 9, design: .monospaced))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .frame(height: 44, alignment: .bottom)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Four uncalibrated ambient spectral channels")
    }
  }
}

private struct AmbientLightInterpretationPanel: View {
  let rawValue: Double
  let historyValues: [Double]
  let calibration: AmbientLuxCalibration?
  let onSetCalibration: (Double, Double) -> Void
  let onClearCalibration: () -> Void
  let onExportCalibration: () -> Void
  let onImportCalibration: () -> Void

  @State private var referenceLuxText = ""

  private var statistics: SensorSeriesStatistics? {
    SensorSeriesStatistics(values: historyValues.isEmpty ? [rawValue] : historyValues)
  }

  private var enteredLux: Double? {
    guard let value = Double(referenceLuxText), value.isFinite, value > 0 else { return nil }
    return value
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let statistics {
        HStack(spacing: 8) {
          ExperimentMetric(label: "Min", value: formatted(statistics.minimum))
          ExperimentMetric(label: "Average", value: formatted(statistics.average))
          ExperimentMetric(label: "Max", value: formatted(statistics.maximum))
        }
        if let position = statistics.relativePosition {
          ProgressView(value: position) {
            Text("Position in observed raw range")
          } currentValueLabel: {
            Text(position.formatted(.percent.precision(.fractionLength(0))))
          }
          .font(.caption)
        }
      }

      Divider()
      if let calibration,
        let estimate = calibration.estimatedLux(for: rawValue)
      {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Estimated illuminance")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("\(SensorFormatting.decimal(estimate, fractionDigits: 1)) lux")
              .font(.title3.bold())
              .monospacedDigit()
          }
          Spacer()
          Text("Estimated")
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
        }
        Text(
          "Single-point scale: \(SensorFormatting.decimal(calibration.luxReference, fractionDigits: 1)) lux at raw \(SensorFormatting.decimal(calibration.rawReference, fractionDigits: 3))."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      HStack {
        TextField("Reference lux", text: $referenceLuxText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 110)
        Button("Calibrate at Current Raw") { captureCalibration() }
          .disabled(enteredLux == nil || rawValue <= 0 || !rawValue.isFinite)
        if calibration != nil {
          Button("Clear") { clearCalibration() }
        }
      }
      HStack {
        Button("Import Calibration…") { onImportCalibration() }
        if calibration != nil {
          Button("Export Calibration…") { onExportCalibration() }
        }
      }
      Text(
        "Requires an external lux reference. This is a one-point estimate, not a certified meter."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .padding(.top, 4)
  }

  private func captureCalibration() {
    guard let enteredLux,
      AmbientLuxCalibration(rawReference: rawValue, luxReference: enteredLux) != nil
    else { return }
    onSetCalibration(rawValue, enteredLux)
  }

  private func clearCalibration() {
    onClearCalibration()
    referenceLuxText = ""
  }

  private func formatted(_ value: Double) -> String {
    SensorFormatting.decimal(value, fractionDigits: 2)
  }
}

private struct LidReferencePanel: View {
  let currentAngle: Double

  @AppStorage("dev.macsensorlab.lid.hasReference") private var hasReference = false
  @AppStorage("dev.macsensorlab.lid.referenceAngle") private var referenceAngle = 0.0

  private var measurement: RelativeAngleMeasurement? {
    guard hasReference else { return nil }
    return RelativeAngleMeasurement(current: currentAngle, reference: referenceAngle)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let measurement {
        HStack(spacing: 8) {
          ExperimentMetric(
            label: "Reference",
            value: "\(SensorFormatting.decimal(measurement.reference, fractionDigits: 1))°")
          ExperimentMetric(
            label: "Relative change",
            value: "\(signed(measurement.delta))°")
        }
        Text(measurement.delta >= 0 ? "Opened from reference" : "Closed from reference")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      HStack {
        Button(hasReference ? "Update Reference" : "Set Current as Reference") {
          referenceAngle = currentAngle
          hasReference = true
        }
        if hasReference {
          Button("Clear") { hasReference = false }
        }
      }
      Text("Relative change is derived from the raw lid angle and does not alter the sensor.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding(.top, 4)
  }

  private func signed(_ value: Double) -> String {
    value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))
  }
}

private struct ExperimentMetric: View {
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
    .padding(7)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
  }
}

private struct DiagnosticsView: View {
  let snapshots: [SensorSnapshot]
  let samplingCadence: SamplingCadence
  let isSamplingPaused: Bool
  let isDemoMode: Bool
  let lastRefreshDate: Date?
  let recordingFileName: String?
  let recordingProgress: SensorCSVRecordingProgress?
  let message: String?
  let onExportDiagnostics: () -> Void

  var body: some View {
    Form {
      Section("Build") {
        LabeledContent("Version", value: AppBuildInfo.version)
        LabeledContent(
          "Data mode", value: isDemoMode ? "Built-in demo fixtures" : "Live hardware")
        LabeledContent("Sensor providers", value: "\(snapshots.count)")
        LabeledContent("Privacy manifest", value: AppBuildInfo.privacyManifestStatus)
      }
      Section("Provider health") {
        LabeledContent("Available", value: "\(snapshots.filter { $0.status == .available }.count)")
        LabeledContent("Limited", value: "\(snapshots.filter { $0.status == .degraded }.count)")
        LabeledContent(
          "Unavailable",
          value:
            "\(snapshots.filter { [.unavailable, .permissionRequired, .error].contains($0.status) }.count)"
        )
      }
      Section("Sampling & recording") {
        LabeledContent(
          "Automatic sampling",
          value: isSamplingPaused ? "Paused" : samplingCadence.displayName)
        if let lastRefreshDate {
          LabeledContent(
            "Last refresh", value: lastRefreshDate.formatted(date: .omitted, time: .standard))
        }
        if let recordingFileName {
          LabeledContent("Recording", value: recordingFileName)
          if let recordingProgress {
            ProgressView(value: recordingProgress.fractionUsed) {
              Text("50 MB safety limit")
            } currentValueLabel: {
              Text(
                "\(recordingProgress.rowCount) rows • \(SensorFormatting.bytes(UInt64(recordingProgress.byteCount)))"
              )
            }
          }
        } else {
          LabeledContent("Continuous recording", value: "Off")
        }
        Text("Chart history stays in memory only and can be cleared from the toolbar.")
          .foregroundStyle(.secondary)
      }
      Section("Privacy") {
        Text(
          "No serial number, hardware UUID, UDID, host name, user name, location, process list, SSID or audio recording is collected by this build."
        )
        Text(
          "All readings stay on this Mac unless you explicitly export a snapshot, recording, calibration, or diagnostics file."
        )
      }
      Section("Support") {
        Button("Export Privacy-Safe Diagnostics…") { onExportDiagnostics() }
        Text(
          "The support report contains provider status and stable channel metadata, never sensor readings, notes, source strings, machine identifiers, or file paths."
        )
        .foregroundStyle(.secondary)
      }
      Section("Safety") {
        Text(
          "This build never runs as root, changes fan settings, writes SMC values, or modifies Apple SPU driver state."
        )
        Text("Experimental readings are not medical, legal, safety, or calibrated metrology data.")
      }
      if let message {
        Section("Last action") { Text(message) }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Diagnostics")
  }
}

enum AppBuildInfo {
  static let version: String = {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return switch (version, build) {
    case (.some(let version), .some(let build)): "\(version) (\(build))"
    case (.some(let version), .none): version
    default: "Development"
    }
  }()

  static let privacyManifestStatus =
    Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") == nil
    ? "Development executable" : "Included"
}
