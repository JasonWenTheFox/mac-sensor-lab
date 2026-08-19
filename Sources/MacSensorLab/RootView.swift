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
      Group {
        switch model.selection ?? .overview {
        case .overview:
          OverviewView(snapshots: model.snapshots, history: model.history)
        case .rawSensors:
          RawSensorsView(snapshots: model.snapshots)
        case .experiments:
          ExperimentsView(snapshots: model.snapshots, history: model.history)
        case .diagnostics:
          DiagnosticsView(
            snapshots: model.snapshots,
            samplingCadence: model.samplingCadence,
            isSamplingPaused: model.isSamplingPaused,
            lastRefreshDate: model.lastRefreshDate,
            recordingFileName: model.recordingFileName,
            recordingProgress: model.recordingProgress,
            message: model.lastActionMessage
          )
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
  private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text("Overview")
          .font(.largeTitle.bold())
        Text("Live local readings, with source and confidence kept visible.")
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

  var body: some View {
    List {
      ForEach(snapshots) { snapshot in
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
          Text("Source: \(snapshot.source) • \(snapshot.capability.displayName)")
        }
      }
    }
    .navigationTitle("Raw Sensors")
  }
}

private func shouldDisplayUnit(_ unit: String, for channel: SensorChannel) -> Bool {
  guard unit != "bytes" else { return false }
  return !channel.formattedValue.contains(unit)
}

private struct ExperimentsView: View {
  let snapshots: [SensorSnapshot]
  let history: [String: [SensorHistoryPoint]]

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
    guard let snapshot,
      [.available, .degraded].contains(snapshot.status),
      let channelID = experiment.channelID
    else { return false }
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
      }

      let points = history["\(snapshot.id)/\(channelID)", default: []]
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

private struct DiagnosticsView: View {
  let snapshots: [SensorSnapshot]
  let samplingCadence: SamplingCadence
  let isSamplingPaused: Bool
  let lastRefreshDate: Date?
  let recordingFileName: String?
  let recordingProgress: SensorCSVRecordingProgress?
  let message: String?

  var body: some View {
    Form {
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
        Text("All readings stay on this Mac unless you explicitly export a snapshot.")
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
