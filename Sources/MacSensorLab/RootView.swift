import Charts
import SensorCore
import SwiftUI

struct RootView: View {
  @ObservedObject var model: SensorDashboardModel

  var body: some View {
    NavigationSplitView {
      List(DashboardSection.allCases, selection: $model.selection) { section in
        Label(section.displayName, systemImage: section.symbol)
          .tag(section)
      }
      .navigationTitle("Mac Sensor Lab")
      .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    } detail: {
      VStack(spacing: 0) {
        if model.isDemoMode {
          Label(L10n.text("Demo data — not live sensor readings"), systemImage: "testtube.2")
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
              isDemoMode: model.isDemoMode,
              samplingHealth: model.samplingHealth,
              onReviewIssues: { model.selection = .rawSensors },
              onViewDiagnostics: { model.selection = .diagnostics }
            )
          case .rawSensors:
            RawSensorsView(snapshots: model.snapshots)
          case .experiments:
            ExperimentsView(
              snapshots: model.snapshots,
              history: model.history,
              isDemoMode: model.isDemoMode,
              ambientLuxCalibration: model.ambientLuxCalibration,
              ambientSpectralReference: model.ambientSpectralReference,
              onSetAmbientCalibration: model.setAmbientLuxCalibration,
              onUndoAmbientCalibrationPoint: model.undoLastAmbientLuxCalibrationPoint,
              onClearAmbientCalibration: model.clearAmbientLuxCalibration,
              onExportAmbientCalibration: model.exportAmbientLuxCalibration,
              onImportAmbientCalibration: model.importAmbientLuxCalibration,
              onSetAmbientSpectralReference: model.setAmbientSpectralReference,
              onClearAmbientSpectralReference: model.clearAmbientSpectralReference
            )
          case .diagnostics:
            DiagnosticsView(
              snapshots: model.snapshots,
              samplingCadence: model.samplingCadence,
              isSamplingPaused: model.isSamplingPaused,
              isDemoMode: model.isDemoMode,
              lastRefreshDate: model.lastRefreshDate,
              samplingHealth: model.samplingHealth,
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
            Picker(L10n.text("Refresh interval"), selection: $model.samplingCadence) {
              ForEach(SamplingCadence.allCases) { cadence in
                Text(cadence.displayName).tag(cadence)
              }
            }
            Divider()
            Button(
              L10n.text(
                model.isSamplingPaused
                  ? "Resume Automatic Sampling" : "Pause Automatic Sampling"
              )
            ) {
              model.toggleSampling()
            }
            Button(L10n.text("Clear Chart History")) { model.clearHistory() }
          } label: {
            Label(
              model.isSamplingPaused
                ? L10n.text("Paused") : model.samplingCadence.shortLabel,
              systemImage: model.isSamplingPaused ? "pause.circle" : "timer")
          }
          .help(L10n.text("Sampling controls"))

          if model.isRecording {
            Button {
              Task { await model.stopRecording() }
            } label: {
              Label(L10n.text("Stop Recording"), systemImage: "record.circle.fill")
                .foregroundStyle(.red)
            }
            .help(L10n.text("Stop continuous CSV recording"))
          }

          Menu {
            Button(L10n.text("JSON Snapshot")) { model.export(.json) }
            Button(L10n.text("CSV Channels")) { model.export(.csv) }
            Divider()
            if model.isRecording {
              Button(L10n.text("Stop Continuous Recording")) {
                Task { await model.stopRecording() }
              }
            } else {
              Button(L10n.text("Start Continuous CSV Recording…")) { model.startRecording() }
            }
          } label: {
            Label(L10n.text("Export"), systemImage: "square.and.arrow.up")
          }
          Button {
            Task { await model.refresh() }
          } label: {
            Label(L10n.text("Refresh"), systemImage: "arrow.clockwise")
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
  let samplingHealth: SensorSamplingHealth
  let onReviewIssues: () -> Void
  let onViewDiagnostics: () -> Void
  private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.text("Overview"))
          .font(.largeTitle.bold())
        Text(
          L10n.text(
            isDemoMode
              ? "Deterministic fixture readings for screenshots and UI review."
              : "Live local readings, with source and confidence kept visible."
          )
        )
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 12)

      ProviderHealthSummary(
        snapshots: snapshots,
        samplingHealth: samplingHealth,
        onReviewIssues: onReviewIssues,
        onViewDiagnostics: onViewDiagnostics
      )
      .padding(.bottom, 16)

      LazyVGrid(columns: columns, spacing: 16) {
        ForEach(snapshots) { snapshot in
          SensorCard(snapshot: snapshot, history: history)
        }
      }
    }
    .padding(24)
    .navigationTitle(L10n.text("Overview"))
  }
}

struct ProviderHealthSummaryState {
  struct Metric: Identifiable {
    let status: SensorStatus
    let count: Int

    var id: String { status.rawValue }
  }

  let metrics: [Metric]
  let hasReviewableIssues: Bool
  let statusTransitionCount: Int

  init(snapshots: [SensorSnapshot], samplingHealth: SensorSamplingHealth) {
    let counts = SensorStatusCounts(snapshots: snapshots)
    metrics = [
      Metric(status: .available, count: counts.available),
      Metric(status: .loading, count: counts.loading),
      Metric(status: .degraded, count: counts.degraded),
      Metric(status: .permissionRequired, count: counts.permissionRequired),
      Metric(status: .unavailable, count: counts.unavailable),
      Metric(status: .error, count: counts.error),
    ].filter { $0.count > 0 }
    hasReviewableIssues =
      counts.degraded + counts.permissionRequired + counts.unavailable + counts.error > 0
    statusTransitionCount = samplingHealth.totalStatusTransitionCount
  }
}

private struct ProviderHealthSummary: View {
  let snapshots: [SensorSnapshot]
  let samplingHealth: SensorSamplingHealth
  let onReviewIssues: () -> Void
  let onViewDiagnostics: () -> Void

  private var state: ProviderHealthSummaryState {
    ProviderHealthSummaryState(snapshots: snapshots, samplingHealth: samplingHealth)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(L10n.text("Provider health"), systemImage: "heart.text.square")
          .font(.headline)
        Spacer()
        if state.hasReviewableIssues {
          Button(L10n.text("Review Raw Sensors"), action: onReviewIssues)
            .buttonStyle(.link)
        }
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          ForEach(state.metrics) { metric in
            ProviderHealthMetric(status: metric.status, count: metric.count)
          }
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
          ForEach(state.metrics) { metric in
            ProviderHealthMetric(status: metric.status, count: metric.count)
          }
        }
      }
      if state.statusTransitionCount > 0 {
        HStack {
          Label(
            L10n.format(
              "%lld status changes this launch",
              Int64(state.statusTransitionCount)
            ),
            systemImage: "arrow.triangle.2.circlepath"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Spacer()
          Button(L10n.text("View Diagnostics"), action: onViewDiagnostics)
            .buttonStyle(.link)
            .font(.caption)
        }
      }
    }
    .padding(14)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.quaternary, lineWidth: 1)
    }
  }
}

private struct ProviderHealthMetric: View {
  let status: SensorStatus
  let count: Int

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(sensorStatusColor(status))
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 1) {
        Text("\(count)")
          .font(.headline.monospacedDigit())
        Text(L10n.text(status.displayName))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(minWidth: 94, maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(sensorStatusColor(status).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityElement(children: .combine)
  }
}

private struct SensorCard: View {
  let snapshot: SensorSnapshot
  let history: [String: [SensorHistoryPoint]]

  private var chartChannel: SensorChannel? {
    SensorHistoryRetention.overviewChannelPriority.lazy.compactMap { id in
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
          Text(L10n.sensorText(snapshot.name))
            .font(.headline)
          Text(L10n.sensorText(snapshot.summary))
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
            Text(L10n.sensorText(channel.label))
              .foregroundStyle(.secondary)
            Spacer()
            Text(L10n.sensorText(channel.formattedValue))
              .monospacedDigit()
            if let unit = channel.unit, shouldDisplayUnit(unit, for: channel) {
              Text(L10n.sensorText(unit)).foregroundStyle(.secondary)
            }
          }
          .font(.callout)
        }
      }

      if let channel = chartChannel, chartPoints.count >= 2 {
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.format("%@ • recent samples", L10n.sensorText(channel.label)))
            .font(.caption2)
            .foregroundStyle(.secondary)
          Chart(chartPoints) { point in
            LineMark(
              x: .value("Time", point.timestamp),
              y: .value(L10n.sensorText(channel.label), point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor)
            AreaMark(
              x: .value("Time", point.timestamp),
              y: .value(L10n.sensorText(channel.label), point.value)
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
        .accessibilityLabel(
          L10n.format(
            "%@ trend with %lld samples",
            L10n.sensorText(channel.label),
            Int64(chartPoints.count)
          )
        )
      }

      Divider()
      HStack(spacing: 8) {
        Label {
          Text(L10n.text("Updated ")) + Text(snapshot.timestamp, style: .relative)
        } icon: {
          Image(systemName: "clock")
        }
        .help(
          L10n.format(
            "Original sample time: %@",
            snapshot.timestamp.formatted(date: .abbreviated, time: .standard)
          )
        )
        Spacer()
        Text(L10n.text(snapshot.capability.displayName))
      }
      .font(.caption)
      .foregroundStyle(.tertiary)

      Text(L10n.format("Source: %@", L10n.sensorText(snapshot.source)))
        .font(.caption)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .help(snapshot.source)
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
    sensorStatusColor(status)
  }

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(L10n.text(status.displayName))
    }
    .font(.caption.weight(.medium))
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(color.opacity(0.12), in: Capsule())
  }
}

private func sensorStatusColor(_ status: SensorStatus) -> Color {
  switch status {
  case .available: .green
  case .loading: .blue
  case .degraded: .orange
  case .permissionRequired: .yellow
  case .unavailable: .gray
  case .error: .red
  }
}

private struct RawSensorsView: View {
  let snapshots: [SensorSnapshot]
  @State private var query = ""

  private var filteredSnapshots: [SensorSnapshot] {
    SensorSnapshotSearch.filter(
      snapshots,
      query: query,
      localizedDisplayText: L10n.sensorText
    )
  }

  var body: some View {
    List {
      if filteredSnapshots.isEmpty {
        ContentUnavailableView(
          L10n.text("No Sensors Found"),
          systemImage: "magnifyingglass",
          description: Text(
            L10n.text("Try a provider, channel, source, status, or stable ID.")
          )
        )
      }
      ForEach(filteredSnapshots) { snapshot in
        Section {
          ForEach(snapshot.channels) { channel in
            VStack(alignment: .leading, spacing: 5) {
              HStack(alignment: .firstTextBaseline) {
                Text(L10n.sensorText(channel.label))
                Spacer()
                Text(L10n.sensorText(channel.formattedValue)).monospacedDigit()
                if let unit = channel.unit, shouldDisplayUnit(unit, for: channel) {
                  Text(L10n.sensorText(unit)).foregroundStyle(.secondary)
                }
              }
              HStack(spacing: 8) {
                Text(channel.id).monospaced()
                Text(L10n.text(channel.kind.displayName))
                if let note = channel.note { Text(L10n.sensorText(note)) }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
          }
          if snapshot.channels.isEmpty {
            Text(L10n.sensorText(snapshot.summary)).foregroundStyle(.secondary)
          }
          ForEach(snapshot.notes, id: \.self) { note in
            Label(L10n.sensorText(note), systemImage: "info.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } header: {
          HStack {
            Text(L10n.sensorText(snapshot.name))
            Spacer()
            StatusPill(status: snapshot.status)
          }
        } footer: {
          Text(
            L10n.format(
              "Updated %@ • Source: %@ • %@",
              snapshot.timestamp.formatted(date: .omitted, time: .standard),
              L10n.sensorText(snapshot.source),
              L10n.text(snapshot.capability.displayName)
            )
          )
        }
      }
    }
    .navigationTitle(L10n.text("Raw Sensors"))
    .searchable(
      text: $query,
      prompt: L10n.text("Provider, channel, source, status, or ID")
    )
  }
}

private func shouldDisplayUnit(_ unit: String, for channel: SensorChannel) -> Bool {
  guard unit != "bytes", unit != "bytes/s" else { return false }
  return !channel.formattedValue.contains(unit)
}

private struct ExperimentsView: View {
  let snapshots: [SensorSnapshot]
  let history: [String: [SensorHistoryPoint]]
  let isDemoMode: Bool
  let ambientLuxCalibration: AmbientLuxCalibration?
  let ambientSpectralReference: AmbientSpectralFingerprint?
  let onSetAmbientCalibration: (Double, Double) -> Void
  let onUndoAmbientCalibrationPoint: () -> Void
  let onClearAmbientCalibration: () -> Void
  let onExportAmbientCalibration: () -> Void
  let onImportAmbientCalibration: () -> Void
  let onSetAmbientSpectralReference: ([Double]) -> Void
  let onClearAmbientSpectralReference: () -> Void

  private struct Experiment {
    let name: String
    let symbol: String
    let providerID: String?
    let channelID: String?
    let description: String
  }

  private let experiments = [
    Experiment(
      name: L10n.text("Battery Trend"), symbol: "battery.100percent",
      providerID: "power.source", channelID: "battery_charge",
      description: L10n.text(
        "Uses recent public charge history; shown only while discharging"
      )),
    Experiment(
      name: L10n.text("Thermal Trend"), symbol: "thermometer.medium",
      providerID: "thermal.pressure", channelID: "thermal_pressure_level",
      description: L10n.text(
        "Tracks public pressure states as an ordinal history, not temperature"
      )),
    Experiment(
      name: L10n.text("Component Thermals"), symbol: "cpu",
      providerID: "thermal.smc", channelID: "cpu_hotspot",
      description: L10n.text(
        "Compares internal CPU and GPU hotspots; not ambient temperature"
      )),
    Experiment(
      name: L10n.text("System Power Trend"), symbol: "bolt.circle",
      providerID: "thermal.smc", channelID: "system_power",
      description: L10n.text(
        "Tracks internal SMC power telemetry; not wall-plug power"
      )),
    Experiment(
      name: L10n.text("Network Throughput"), symbol: "arrow.up.arrow.down",
      providerID: "system.network_throughput", channelID: "network_receive_rate",
      description: L10n.text(
        "Compares recent aggregate receive and send rates"
      )),
    Experiment(
      name: L10n.text("Disk Activity"), symbol: "internaldrive",
      providerID: "storage.disk_io", channelID: "disk_read_rate",
      description: L10n.text(
        "Compares recent aggregate read and write rates"
      )),
    Experiment(
      name: L10n.text("Level"), symbol: "level", providerID: "motion.spu_live",
      channelID: "level_roll",
      description: L10n.text(
        "Uses gravity-derived roll and pitch when live acceleration is available"
      )),
    Experiment(
      name: L10n.text("Lid Protractor"), symbol: "angle", providerID: "motion.lid_angle",
      channelID: "angle",
      description: L10n.text("Uses the undocumented lid-angle sensor")),
    Experiment(
      name: L10n.text("Motion Trend"), symbol: "waveform.path", providerID: "motion.spu_live",
      channelID: "acceleration_magnitude",
      description: L10n.text(
        "Low-rate acceleration variation; not a vibration spectrum analyzer"
      )),
    Experiment(
      name: L10n.text("Light Meter"), symbol: "sun.max", providerID: "motion.spu_live",
      channelID: "ambient_intensity",
      description: L10n.text(
        "Shows raw light first; lux requires model-specific calibration"
      )),
    Experiment(
      name: L10n.text("Light Spectrum"), symbol: "rainbow",
      providerID: "motion.spu_live", channelID: "ambient_spectral_1",
      description: L10n.text(
        "Compares the relative balance of four uncalibrated light channels"
      )),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.text("Experiments")).font(.largeTitle.bold())
        Text(L10n.text("Choose a tool to interpret, compare, or calibrate recent sensor data."))
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
    .navigationTitle(L10n.text("Experiments"))
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
    if isReady {
      return L10n.text(
        snapshot?.status == .degraded ? "Recent data • source limited" : "Data source ready"
      )
    }
    guard let snapshot else { return L10n.text("In development") }
    if snapshot.id == "diagnostics.hardware_capabilities",
      snapshot.channels.contains(where: { ($0.value ?? 0) > 0 })
    {
      return L10n.text("Hardware detected • measurement in development")
    }
    return switch snapshot.status {
    case .loading: L10n.text("Checking data source")
    case .permissionRequired: L10n.text("Permission required")
    case .unavailable: L10n.text("Data source unavailable")
    case .error: L10n.text("Data source error")
    case .degraded: L10n.text("Data source limited")
    case .available: L10n.text("Required reading unavailable")
    }
  }

  @ViewBuilder
  private func liveReading(for experiment: Experiment, snapshot: SensorSnapshot) -> some View {
    if let channelID = experiment.channelID,
      let channel = snapshot.channels.first(where: { $0.id == channelID && $0.value != nil })
    {
      let points = history["\(snapshot.id)/\(channelID)", default: []]
      HStack(alignment: .firstTextBaseline) {
        Text(L10n.sensorText(channel.formattedValue))
          .font(.title2.bold())
          .monospacedDigit()
        if let unit = channel.unit, shouldDisplayUnit(unit, for: channel) {
          Text(L10n.sensorText(unit)).foregroundStyle(.secondary)
        }
        Spacer()
        Text(L10n.text(channel.kind.displayName))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if channelID == "angle", let value = channel.value {
        Gauge(value: min(max(value, 0), 360), in: 0...360) {
          Text(L10n.text("Lid angle"))
        } currentValueLabel: {
          Text("0° — 360°").font(.caption2)
        }
        .gaugeStyle(.linearCapacity)
        LidReferencePanel(currentAngle: value, isDemoMode: isDemoMode)
      }

      if channelID == "level_roll",
        let pitch = snapshot.channels.first(where: { $0.id == "level_pitch" })
      {
        HStack {
          Label(
            L10n.format("Roll %@°", channel.formattedValue),
            systemImage: "arrow.left.and.right"
          )
          Spacer()
          Label(
            L10n.format("Pitch %@°", pitch.formattedValue),
            systemImage: "arrow.up.and.down"
          )
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
            onUndoCalibrationPoint: onUndoAmbientCalibrationPoint,
            onClearCalibration: onClearAmbientCalibration,
            onExportCalibration: onExportAmbientCalibration,
            onImportCalibration: onImportAmbientCalibration
          )
        }
      }

      if channelID == "ambient_spectral_1" {
        AmbientSpectrumPanel(
          channels: snapshot.channels.filter { $0.id.hasPrefix("ambient_spectral_") },
          reference: ambientSpectralReference,
          onSetReference: onSetAmbientSpectralReference,
          onClearReference: onClearAmbientSpectralReference
        )
      }

      if channelID == "acceleration_magnitude",
        let statistics = MotionVariationStatistics(values: points.map(\.value))
      {
        HStack(spacing: 8) {
          ExperimentMetric(
            label: L10n.text("RMS variation"),
            value: "\(SensorFormatting.decimal(statistics.rmsDeviation, fractionDigits: 4)) g")
          ExperimentMetric(
            label: L10n.text("Peak-to-peak"),
            value: "\(SensorFormatting.decimal(statistics.peakToPeak, fractionDigits: 4)) g")
        }
        Text(
          L10n.format(
            "Calculated from %lld dashboard samples. The 1–10 second cadence cannot measure vibration frequency.",
            Int64(statistics.sampleCount)
          )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      if channelID == "battery_charge" {
        BatteryTrendPanel(
          points: points,
          isDischarging: BatteryDischargeEstimate.isEligible(snapshot: snapshot)
        )
      }

      if channelID == "thermal_pressure_level",
        let trend = ThermalPressureTrend(points: points)
      {
        HStack(spacing: 8) {
          ExperimentMetric(
            label: L10n.text("Highest recent pressure"),
            value: L10n.sensorText(trend.highest.displayName)
          )
          ExperimentMetric(
            label: L10n.text("State changes"),
            value: "\(trend.transitionCount)"
          )
        }
        Text(
          L10n.format(
            "%lld samples retained. Ordinal spacing is not physical and no temperature is inferred.",
            Int64(trend.sampleCount)
          )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      if channelID == "system_power",
        let statistics = SensorSeriesStatistics(values: points.map(\.value))
      {
        HStack(spacing: 8) {
          ExperimentMetric(
            label: L10n.text("Average"),
            value: "\(SensorFormatting.decimal(statistics.average, fractionDigits: 2)) W"
          )
          ExperimentMetric(
            label: L10n.text("Max"),
            value: "\(SensorFormatting.decimal(statistics.maximum, fractionDigits: 2)) W"
          )
        }
        Text(L10n.sensorText("Internal SMC telemetry; not wall-plug power."))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if channelID == "cpu_hotspot",
        let gpuChannel = snapshot.channels.first(where: { $0.id == "gpu_hotspot" })
      {
        PairedSeriesPanel(
          primaryChannel: channel,
          primaryPoints: points,
          secondaryChannel: gpuChannel,
          secondaryPoints: history["\(snapshot.id)/gpu_hotspot", default: []],
          caution: "Internal component temperature, not ambient room temperature.",
          formatAverage: {
            "\(SensorFormatting.decimal($0, fractionDigits: 1)) °C"
          }
        )
      } else if let pair = pairedRateDefinition(for: channelID),
        let secondaryChannel = snapshot.channels.first(where: { $0.id == pair.channelID })
      {
        PairedSeriesPanel(
          primaryChannel: channel,
          primaryPoints: points,
          secondaryChannel: secondaryChannel,
          secondaryPoints: history["\(snapshot.id)/\(pair.channelID)", default: []],
          caution: pair.caution,
          formatAverage: SensorFormatting.bytesPerSecond
        )
      } else if points.count >= 2 {
        Chart(points) { point in
          LineMark(x: .value("Time", point.timestamp), y: .value(channel.label, point.value))
            .interpolationMethod(
              channelID == "thermal_pressure_level" ? .stepEnd : .catmullRom
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 34)
        .accessibilityLabel(
          L10n.format("%@ experiment trend", L10n.sensorText(channel.label))
        )
      }
    }
  }

  private func pairedRateDefinition(for channelID: String) -> (channelID: String, caution: String)?
  {
    switch channelID {
    case "network_receive_rate":
      (
        "network_send_rate",
        "Virtual or tunneled paths can represent the same traffic more than once."
      )
    case "disk_read_rate":
      (
        "disk_write_rate",
        "Totals are driver-lifetime counters aggregated across block-storage drivers."
      )
    default: nil
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
            Text(L10n.sensorText(channel.formattedValue))
              .font(.system(size: 9, design: .monospaced))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .frame(height: 44, alignment: .bottom)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(L10n.text("Four uncalibrated ambient spectral channels"))
    }
  }
}

private struct AmbientSpectrumPanel: View {
  let channels: [SensorChannel]
  let reference: AmbientSpectralFingerprint?
  let onSetReference: ([Double]) -> Void
  let onClearReference: () -> Void

  private var fingerprint: AmbientSpectralFingerprint? {
    let ordered = channels.sorted { $0.id < $1.id }
    guard ordered.count == AmbientSpectralFingerprint.channelCount else { return nil }
    return AmbientSpectralFingerprint(values: ordered.compactMap(\.value))
  }

  var body: some View {
    if let fingerprint {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.text("Relative channel balance"))
          .font(.caption.weight(.medium))
        HStack(spacing: 8) {
          ForEach(Array(fingerprint.components.enumerated()), id: \.offset) { index, value in
            VStack(spacing: 4) {
              ProgressView(value: value)
                .progressViewStyle(.linear)
              Text(L10n.format("Spectral channel %lld", Int64(index + 1)))
                .font(.caption2)
              Text(value.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption2.monospacedDigit())
            }
            .frame(maxWidth: .infinity)
          }
        }

        if let reference {
          let distance = fingerprint.distance(to: reference)
          HStack(spacing: 8) {
            ExperimentMetric(
              label: L10n.text("Match to reference"),
              value: (1 - distance).formatted(.percent.precision(.fractionLength(0)))
            )
            if let channel = fingerprint.largestShiftChannel(comparedTo: reference) {
              ExperimentMetric(
                label: L10n.text("Largest shift"),
                value: L10n.format("Spectral channel %lld", Int64(channel + 1))
              )
            }
          }
        }

        HStack {
          Button(L10n.text(reference == nil ? "Set Current as Reference" : "Replace Reference")) {
            onSetReference(fingerprint.components)
          }
          if reference != nil {
            Button(L10n.text("Clear Reference")) { onClearReference() }
          }
        }
        Text(
          L10n.text(
            "This fingerprint compares light sources on this Mac; it is not a color-temperature measurement."
          )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
      .padding(.top, 4)
    }
  }
}

private struct PairedSeriesPanel: View {
  let primaryChannel: SensorChannel
  let primaryPoints: [SensorHistoryPoint]
  let secondaryChannel: SensorChannel
  let secondaryPoints: [SensorHistoryPoint]
  let caution: String
  let formatAverage: (Double) -> String

  private var primaryStatistics: SensorSeriesStatistics? {
    SensorSeriesStatistics(values: primaryPoints.map(\.value))
  }

  private var secondaryStatistics: SensorSeriesStatistics? {
    SensorSeriesStatistics(values: secondaryPoints.map(\.value))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let primaryStatistics, let secondaryStatistics {
        HStack(spacing: 8) {
          ExperimentMetric(
            label: L10n.sensorText(primaryChannel.label),
            value: L10n.format(
              "Average %@",
              formatAverage(primaryStatistics.average)
            )
          )
          ExperimentMetric(
            label: L10n.sensorText(secondaryChannel.label),
            value: L10n.format(
              "Average %@",
              formatAverage(secondaryStatistics.average)
            )
          )
        }
      }

      if primaryPoints.count >= 2, secondaryPoints.count >= 2 {
        HStack(spacing: 12) {
          Label(L10n.sensorText(primaryChannel.label), systemImage: "circle.fill")
            .foregroundStyle(.blue)
          Label(L10n.sensorText(secondaryChannel.label), systemImage: "circle.fill")
            .foregroundStyle(.purple)
        }
        .font(.caption2)

        Chart {
          ForEach(primaryPoints) { point in
            LineMark(
              x: .value("Time", point.timestamp),
              y: .value(primaryChannel.label, point.value)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(.blue)
          }
          ForEach(secondaryPoints) { point in
            LineMark(
              x: .value("Time", point.timestamp),
              y: .value(secondaryChannel.label, point.value)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(.purple)
          }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 44)
        .accessibilityLabel(
          L10n.format(
            "%@ and %@ recent trends",
            L10n.sensorText(primaryChannel.label),
            L10n.sensorText(secondaryChannel.label)
          )
        )
      }

      Text(L10n.sensorText(caution))
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding(.top, 4)
  }
}

private struct BatteryTrendPanel: View {
  let points: [SensorHistoryPoint]
  let isDischarging: Bool

  private var estimate: BatteryDischargeEstimate? {
    guard isDischarging else { return nil }
    return BatteryDischargeEstimate(points: points)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !isDischarging {
        Text(L10n.text("Trend estimate pauses while connected to power or charging."))
          .font(.caption)
          .foregroundStyle(.secondary)
      } else if let estimate {
        HStack(spacing: 8) {
          ExperimentMetric(
            label: L10n.text("Observed drain"),
            value: L10n.format(
              "%@ %%/hour",
              SensorFormatting.decimal(estimate.percentPerHour, fractionDigits: 1)
            )
          )
          ExperimentMetric(
            label: L10n.text("Projected empty"),
            value: L10n.format(
              "%@ h",
              SensorFormatting.decimal(estimate.estimatedHoursToEmpty, fractionDigits: 1)
            )
          )
        }
        Text(
          L10n.format(
            "Estimated from %lld samples over %@ minutes; workload changes can invalidate it.",
            Int64(estimate.sampleCount),
            SensorFormatting.decimal(estimate.duration / 60, fractionDigits: 0)
          )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      } else {
        Text(
          L10n.text(
            "Waiting for at least five minutes and a measurable charge drop."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.top, 4)
  }
}

private struct AmbientLightInterpretationPanel: View {
  let rawValue: Double
  let historyValues: [Double]
  let calibration: AmbientLuxCalibration?
  let onSetCalibration: (Double, Double) -> Void
  let onUndoCalibrationPoint: () -> Void
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

  private var candidateCalibration: AmbientLuxCalibration? {
    guard let enteredLux else { return nil }
    if let calibration {
      return calibration.addingPoint(rawReference: rawValue, luxReference: enteredLux)
    }
    return AmbientLuxCalibration(rawReference: rawValue, luxReference: enteredLux)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let statistics {
        HStack(spacing: 8) {
          ExperimentMetric(label: L10n.text("Min"), value: formatted(statistics.minimum))
          ExperimentMetric(label: L10n.text("Average"), value: formatted(statistics.average))
          ExperimentMetric(label: L10n.text("Max"), value: formatted(statistics.maximum))
        }
        if let position = statistics.relativePosition {
          ProgressView(value: position) {
            Text(L10n.text("Position in observed raw range"))
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
            Text(L10n.text("Estimated illuminance"))
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("\(SensorFormatting.decimal(estimate, fractionDigits: 1)) lux")
              .font(.title3.bold())
              .monospacedDigit()
          }
          Spacer()
          Text(L10n.text("Estimated"))
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
        }
        Text(calibrationDescription(calibration))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      HStack {
        TextField(L10n.text("Reference lux"), text: $referenceLuxText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 110)
        Button(
          L10n.text(
            calibration == nil ? "Calibrate at Current Raw" : "Add Calibration Point"
          )
        ) {
          captureCalibration()
        }
        .disabled(candidateCalibration == nil)
        if calibration != nil {
          if calibration?.pointCount ?? 0 > 1 {
            Button(L10n.text("Undo Last Point")) { onUndoCalibrationPoint() }
          }
          Button(L10n.text("Clear All")) { clearCalibration() }
        }
      }
      HStack {
        Button(L10n.text("Import Calibration…")) { onImportCalibration() }
        if calibration != nil {
          Button(L10n.text("Export Calibration…")) { onExportCalibration() }
        }
      }
      Text(
        L10n.text(
          "Requires an external lux reference. Add up to eight strictly increasing points; every result remains an estimate, not a certified meter."
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .padding(.top, 4)
  }

  private func captureCalibration() {
    guard let enteredLux, candidateCalibration != nil else { return }
    onSetCalibration(rawValue, enteredLux)
  }

  private func clearCalibration() {
    onClearCalibration()
    referenceLuxText = ""
  }

  private func formatted(_ value: Double) -> String {
    SensorFormatting.decimal(value, fractionDigits: 2)
  }

  private func calibrationDescription(_ calibration: AmbientLuxCalibration) -> String {
    if calibration.pointCount == 1 {
      return
        L10n.format(
          "Single-point scale: %@ lux at raw %@.",
          SensorFormatting.decimal(calibration.luxReference, fractionDigits: 1),
          SensorFormatting.decimal(calibration.rawReference, fractionDigits: 3)
        )
    }
    return
      L10n.format(
        "Linear fit from %lld points • RMSE %@ lux.",
        Int64(calibration.pointCount),
        SensorFormatting.decimal(calibration.rootMeanSquareError, fractionDigits: 1)
      )
  }
}

private struct LidReferencePanel: View {
  let currentAngle: Double

  @AppStorage private var hasReference: Bool
  @AppStorage private var referenceAngle: Double

  init(currentAngle: Double, isDemoMode: Bool) {
    self.currentAngle = currentAngle
    _hasReference = AppStorage(
      wrappedValue: false,
      SensorPreferenceKeys.lidHasReference(isDemoMode: isDemoMode)
    )
    _referenceAngle = AppStorage(
      wrappedValue: 0,
      SensorPreferenceKeys.lidReferenceAngle(isDemoMode: isDemoMode)
    )
  }

  private var measurement: RelativeAngleMeasurement? {
    guard hasReference else { return nil }
    return RelativeAngleMeasurement(current: currentAngle, reference: referenceAngle)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let measurement {
        HStack(spacing: 8) {
          ExperimentMetric(
            label: L10n.text("Reference"),
            value: "\(SensorFormatting.decimal(measurement.reference, fractionDigits: 1))°")
          ExperimentMetric(
            label: L10n.text("Relative change"),
            value: "\(signed(measurement.delta))°")
        }
        Text(
          L10n.text(
            measurement.delta >= 0 ? "Opened from reference" : "Closed from reference"
          )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
      HStack {
        Button(
          L10n.text(hasReference ? "Update Reference" : "Set Current as Reference")
        ) {
          referenceAngle = currentAngle
          hasReference = true
        }
        if hasReference {
          Button(L10n.text("Clear")) { hasReference = false }
        }
      }
      Text(
        L10n.text(
          "Relative change is derived from the raw lid angle and does not alter the sensor."
        )
      )
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
  let samplingHealth: SensorSamplingHealth
  let recordingFileName: String?
  let recordingProgress: SensorCSVRecordingProgress?
  let message: String?
  let onExportDiagnostics: () -> Void

  private var statusCounts: SensorStatusCounts {
    SensorStatusCounts(snapshots: snapshots)
  }

  var body: some View {
    Form {
      Section(L10n.text("Build")) {
        LabeledContent(L10n.text("Version"), value: AppBuildInfo.version)
        LabeledContent(
          L10n.text("Data mode"),
          value: L10n.text(isDemoMode ? "Built-in demo fixtures" : "Live hardware")
        )
        LabeledContent(L10n.text("Sensor providers"), value: "\(snapshots.count)")
        LabeledContent(
          L10n.text("Privacy manifest"),
          value: AppBuildInfo.privacyManifestStatus
        )
      }
      Section(L10n.text("Provider health")) {
        LabeledContent(L10n.text("Available"), value: "\(statusCounts.available)")
        LabeledContent(L10n.text("Limited"), value: "\(statusCounts.degraded)")
        LabeledContent(
          L10n.text("Permission required"),
          value: "\(statusCounts.permissionRequired)"
        )
        LabeledContent(L10n.text("Unavailable"), value: "\(statusCounts.unavailable)")
        LabeledContent(L10n.text("Errors"), value: "\(statusCounts.error)")
        if statusCounts.loading > 0 {
          LabeledContent(L10n.text("Loading"), value: "\(statusCounts.loading)")
        }
        LabeledContent(
          L10n.text("Status changes this launch"),
          value: "\(samplingHealth.totalStatusTransitionCount)"
        )
        ForEach(
          samplingHealth.providers.filter { $0.statusTransitionCount > 0 }
        ) { provider in
          LabeledContent(
            provider.providerID,
            value: L10n.format("%lld changes", Int64(provider.statusTransitionCount))
          )
        }
      }
      if statusCounts.permissionRequired > 0 {
        Section(L10n.text("Permission handling")) {
          Text(
            L10n.format(
              "macOS denied ordinary read access for %lld provider(s). Raw Sensors shows the provider-specific reason.",
              Int64(statusCounts.permissionRequired)
            )
          )
        }
      }
      Section(L10n.text("Sampling & recording")) {
        LabeledContent(
          L10n.text("Automatic sampling"),
          value: isSamplingPaused ? L10n.text("Paused") : samplingCadence.displayName
        )
        if let lastRefreshDate {
          LabeledContent(
            L10n.text("Last refresh"),
            value: lastRefreshDate.formatted(date: .omitted, time: .standard)
          )
        }
        LabeledContent(
          L10n.text("Completed refreshes"),
          value: "\(samplingHealth.completedCycleCount)"
        )
        if let milliseconds = samplingHealth.lastCycleDurationMilliseconds {
          LabeledContent(
            L10n.text("Last refresh duration"),
            value: "\(SensorFormatting.decimal(Double(milliseconds) / 1_000, fractionDigits: 3)) s"
          )
        }
        if let recordingFileName {
          LabeledContent(L10n.text("Recording"), value: recordingFileName)
          if let recordingProgress {
            ProgressView(value: recordingProgress.fractionUsed) {
              Text(L10n.text("50 MB safety limit"))
            } currentValueLabel: {
              Text(
                L10n.format(
                  "%lld rows • %@",
                  Int64(recordingProgress.rowCount),
                  SensorFormatting.bytes(UInt64(recordingProgress.byteCount))
                )
              )
            }
          }
        } else {
          LabeledContent(L10n.text("Continuous recording"), value: L10n.text("Off"))
        }
        Text(L10n.text("Chart history stays in memory only and can be cleared from the toolbar."))
          .foregroundStyle(.secondary)
      }
      Section(L10n.text("Privacy")) {
        Text(
          L10n.text(
            "All readings stay on this Mac unless you explicitly export a snapshot, recording, calibration, or diagnostics file."
          )
        )
      }
      Section(L10n.text("Support")) {
        Button(L10n.text("Export Privacy-Safe Diagnostics…")) { onExportDiagnostics() }
        Text(
          L10n.text(
            "The support report contains sensor availability and channel types, but no readings."
          )
        )
        .foregroundStyle(.secondary)
      }
      Section(L10n.text("Safety")) {
        Text(
          L10n.text(
            "Sensor access is read-only and does not change system settings."
          )
        )
        Text(
          L10n.text(
            "Experimental readings are not medical, legal, safety, or calibrated metrology data."
          )
        )
      }
      if let message {
        Section(L10n.text("Last action")) { Text(message) }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(L10n.text("Diagnostics"))
  }
}

enum AppBuildInfo {
  static let version: String = {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return switch (version, build) {
    case (.some(let version), .some(let build)): "\(version) (\(build))"
    case (.some(let version), .none): version
    default: L10n.text("Development")
    }
  }()

  static let privacyManifestStatus =
    Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") == nil
    ? L10n.text("Development executable") : L10n.text("Included")
}
