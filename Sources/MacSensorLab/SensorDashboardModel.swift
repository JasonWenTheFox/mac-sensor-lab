import AppKit
import Combine
import Foundation
import SensorCore
import UniformTypeIdentifiers

enum DashboardSection: String, CaseIterable, Identifiable {
  case overview = "Overview"
  case rawSensors = "Raw Sensors"
  case experiments = "Experiments"
  case diagnostics = "Diagnostics"

  var id: String { rawValue }

  var symbol: String {
    switch self {
    case .overview: "square.grid.2x2"
    case .rawSensors: "waveform.path.ecg"
    case .experiments: "flask"
    case .diagnostics: "stethoscope"
    }
  }
}

enum SamplingCadence: Double, CaseIterable, Identifiable {
  case oneSecond = 1
  case twoSeconds = 2
  case fiveSeconds = 5
  case tenSeconds = 10

  var id: Double { rawValue }
  var duration: Duration { .seconds(rawValue) }
  var displayName: String {
    rawValue == 1 ? "Every 1 second" : "Every \(Int(rawValue)) seconds"
  }
  var shortLabel: String { "\(Int(rawValue)) s" }
}

struct SensorHistoryPoint: Identifiable {
  let id = UUID()
  let timestamp: Date
  let value: Double
}

@MainActor
final class SensorDashboardModel: ObservableObject {
  let isDemoMode: Bool
  @Published var selection: DashboardSection? = .overview
  @Published var samplingCadence: SamplingCadence {
    didSet {
      guard samplingCadence != oldValue else { return }
      UserDefaults.standard.set(
        samplingCadence.rawValue,
        forKey: samplingCadenceDefaultsKey
      )
    }
  }
  @Published private(set) var snapshots: [SensorSnapshot]
  @Published private(set) var history: [String: [SensorHistoryPoint]] = [:]
  @Published private(set) var isRefreshing = false
  @Published private(set) var isSamplingPaused = false
  @Published private(set) var lastRefreshDate: Date?
  @Published private(set) var recordingFileName: String?
  @Published private(set) var recordingProgress: SensorCSVRecordingProgress?
  @Published private(set) var ambientLuxCalibration: AmbientLuxCalibration?
  @Published var lastActionMessage: String?

  private let providers: [any SensorProvider]
  private let maximumHistoryPoints = 600
  private static let ambientCalibrationDefaultsKey = "dev.macsensorlab.ambientLuxCalibration"
  private static let samplingCadenceDefaultsKey = "dev.macsensorlab.samplingCadence"
  private var recorder: SensorCSVRecorder?

  var isRecording: Bool { recordingFileName != nil }

  private var ambientCalibrationDefaultsKey: String {
    Self.ambientCalibrationDefaultsKey + (isDemoMode ? ".demo" : "")
  }

  private var samplingCadenceDefaultsKey: String {
    Self.samplingCadenceDefaultsKey + (isDemoMode ? ".demo" : "")
  }

  init(
    providers: [any SensorProvider] = SensorProviderRegistry.providers(),
    isDemoMode: Bool = false
  ) {
    self.isDemoMode = isDemoMode
    self.providers = providers
    self.snapshots = providers.map { SensorSnapshot.loading(metadata: $0.metadata) }
    self.ambientLuxCalibration = Self.loadAmbientCalibration(
      key: Self.ambientCalibrationDefaultsKey + (isDemoMode ? ".demo" : ""))
    self.samplingCadence = Self.loadSamplingCadence(
      key: Self.samplingCadenceDefaultsKey + (isDemoMode ? ".demo" : ""))
  }

  func runLiveUpdates() async {
    await refresh()
    while !Task.isCancelled {
      do {
        try await Task.sleep(
          for: isSamplingPaused ? .milliseconds(200) : samplingCadence.duration)
      } catch {
        return
      }
      guard !isSamplingPaused else { continue }
      await refresh()
    }
  }

  func toggleSampling() {
    isSamplingPaused.toggle()
    lastActionMessage =
      isSamplingPaused ? "Automatic sampling paused" : "Automatic sampling resumed"
    if !isSamplingPaused {
      Task { await refresh() }
    }
  }

  func clearHistory() {
    history.removeAll(keepingCapacity: true)
    lastActionMessage = "Cleared in-memory chart history"
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true

    let order = Dictionary(
      uniqueKeysWithValues: providers.enumerated().map { ($0.element.metadata.id, $0.offset) })
    await withTaskGroup(of: SensorSnapshot.self) { group in
      for provider in providers {
        group.addTask { await provider.read() }
      }
      for await snapshot in group {
        guard !Task.isCancelled else { break }
        let snapshotWithDerivations = applyingUserDerivations(to: snapshot)
        if let index = snapshots.firstIndex(where: { $0.id == snapshotWithDerivations.id }) {
          snapshots[index] = snapshotWithDerivations
        } else {
          snapshots.append(snapshotWithDerivations)
        }
        appendHistory(snapshotWithDerivations)
        snapshots.sort { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
      }
    }
    isRefreshing = false
    lastRefreshDate = .now
    await appendRecordingBatch()
  }

  private func appendHistory(_ snapshot: SensorSnapshot) {
    for channel in snapshot.channels {
      guard let value = channel.value, value.isFinite else { continue }
      let key = "\(snapshot.id)/\(channel.id)"
      var points = history[key, default: []]
      guard points.last?.timestamp != snapshot.timestamp else { continue }
      points.append(SensorHistoryPoint(timestamp: snapshot.timestamp, value: value))
      if points.count > maximumHistoryPoints {
        points.removeFirst(points.count - maximumHistoryPoints)
      }
      history[key] = points
    }
  }

  func export(_ format: ExportFormat) {
    let panel = NSSavePanel()
    panel.title = "Export Sensor Snapshot"
    panel.nameFieldStringValue = "mac-sensor-lab-snapshot.\(format.fileExtension)"
    panel.allowedContentTypes = [format.contentType]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let data =
        switch format {
        case .json: try SensorExportService.jsonData(snapshots)
        case .csv: SensorExportService.csvData(snapshots)
        }
      try data.write(to: url, options: .atomic)
      lastActionMessage = "Exported \(url.lastPathComponent)"
    } catch {
      lastActionMessage = "Export failed: \(error.localizedDescription)"
    }
  }

  func exportDiagnostics() {
    let panel = NSSavePanel()
    panel.title = "Export Privacy-Safe Diagnostics"
    panel.message =
      "Includes provider status and stable channel metadata, but no sensor readings or machine identifiers."
    panel.nameFieldStringValue = "mac-sensor-lab-diagnostics-\(Self.fileTimestamp()).json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let data = try SensorDiagnosticsExportService.jsonData(
        snapshots,
        applicationVersion: AppBuildInfo.version + (isDemoMode ? " demo" : "")
      )
      try data.write(to: url, options: .atomic)
      lastActionMessage = "Exported privacy-safe diagnostics \(url.lastPathComponent)"
    } catch {
      lastActionMessage = "Diagnostics export failed: \(error.localizedDescription)"
    }
  }

  func startRecording() {
    guard recorder == nil else { return }
    let panel = NSSavePanel()
    panel.title = "Start Continuous Sensor Recording"
    panel.message = "Recording is local, append-only, and stops automatically at 50 MB."
    panel.nameFieldStringValue = "mac-sensor-lab-recording-\(Self.fileTimestamp()).csv"
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let recorder = try SensorCSVRecorder(destinationURL: url)
      self.recorder = recorder
      recordingFileName = url.lastPathComponent
      recordingProgress = nil
      lastActionMessage = "Started recording \(url.lastPathComponent)"
      Task { await appendRecordingBatch() }
    } catch {
      lastActionMessage = "Could not start recording: \(error.localizedDescription)"
    }
  }

  func setAmbientLuxCalibration(rawReference: Double, luxReference: Double) {
    guard
      let calibration = AmbientLuxCalibration(
        rawReference: rawReference,
        luxReference: luxReference
      )
    else {
      lastActionMessage = "Ambient-light calibration values were invalid"
      return
    }
    ambientLuxCalibration = calibration
    if let data = try? JSONEncoder().encode(calibration) {
      UserDefaults.standard.set(data, forKey: ambientCalibrationDefaultsKey)
    }
    reapplyAmbientCalibration()
    lastActionMessage = "Saved a single-point ambient-light calibration"
  }

  func clearAmbientLuxCalibration() {
    ambientLuxCalibration = nil
    UserDefaults.standard.removeObject(forKey: ambientCalibrationDefaultsKey)
    reapplyAmbientCalibration()
    lastActionMessage = "Cleared ambient-light calibration"
  }

  func exportAmbientLuxCalibration() {
    guard let ambientLuxCalibration else {
      lastActionMessage = "Create an ambient-light calibration before exporting it"
      return
    }
    let panel = NSSavePanel()
    panel.title = "Export Ambient-Light Calibration"
    panel.nameFieldStringValue = "mac-sensor-lab-light-calibration.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      try AmbientLuxCalibrationFileService.data(for: ambientLuxCalibration).write(
        to: url,
        options: .atomic
      )
      lastActionMessage = "Exported light calibration \(url.lastPathComponent)"
    } catch {
      lastActionMessage = "Calibration export failed: \(error.localizedDescription)"
    }
  }

  func importAmbientLuxCalibration() {
    let panel = NSOpenPanel()
    panel.title = "Import Ambient-Light Calibration"
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let calibration = try AmbientLuxCalibrationFileService.read(from: url)
      ambientLuxCalibration = calibration
      if let data = try? JSONEncoder().encode(calibration) {
        UserDefaults.standard.set(data, forKey: ambientCalibrationDefaultsKey)
      }
      reapplyAmbientCalibration()
      lastActionMessage = "Imported light calibration \(url.lastPathComponent)"
    } catch {
      lastActionMessage = "Calibration import failed: \(error.localizedDescription)"
    }
  }

  func stopRecording() async {
    guard let activeRecorder = recorder else { return }
    recorder = nil
    let fileName = recordingFileName ?? activeRecorder.destinationURL.lastPathComponent
    recordingFileName = nil

    do {
      let progress = try await activeRecorder.finish()
      recordingProgress = progress
      lastActionMessage =
        "Stopped \(fileName) after \(progress.rowCount) rows (\(SensorFormatting.bytes(UInt64(progress.byteCount))))"
    } catch {
      lastActionMessage = "Recording stop failed: \(error.localizedDescription)"
    }
  }

  private func appendRecordingBatch() async {
    guard let activeRecorder = recorder else { return }

    do {
      let progress = try await activeRecorder.appendNewSnapshots(snapshots)
      guard recorder === activeRecorder else { return }
      recordingProgress = progress
    } catch {
      guard recorder === activeRecorder else { return }
      recorder = nil
      recordingFileName = nil
      let progress = try? await activeRecorder.finish()
      if let progress { recordingProgress = progress }
      lastActionMessage = "Recording stopped safely: \(error.localizedDescription)"
    }
  }

  private func applyingUserDerivations(to snapshot: SensorSnapshot) -> SensorSnapshot {
    guard snapshot.id == "motion.spu_live" else { return snapshot }
    var channels = snapshot.channels.filter { $0.id != "ambient_estimated_lux" }
    if let calibration = ambientLuxCalibration,
      let rawValue = channels.first(where: { $0.id == "ambient_intensity" })?.value,
      let estimatedChannel = calibration.estimatedChannel(for: rawValue)
    {
      channels.append(estimatedChannel)
    }

    return SensorSnapshot(
      id: snapshot.id,
      name: snapshot.name,
      category: snapshot.category,
      summary: snapshot.summary,
      status: snapshot.status,
      source: snapshot.source,
      capability: snapshot.capability,
      channels: channels,
      notes: snapshot.notes,
      timestamp: snapshot.timestamp
    )
  }

  private func reapplyAmbientCalibration() {
    guard let index = snapshots.firstIndex(where: { $0.id == "motion.spu_live" }) else { return }
    snapshots[index] = applyingUserDerivations(to: snapshots[index])
  }

  private static func loadAmbientCalibration(key: String) -> AmbientLuxCalibration? {
    guard let data = UserDefaults.standard.data(forKey: key) else {
      return nil
    }
    return try? JSONDecoder().decode(AmbientLuxCalibration.self, from: data)
  }

  private static func loadSamplingCadence(key: String) -> SamplingCadence {
    guard UserDefaults.standard.object(forKey: key) != nil else {
      return .twoSeconds
    }
    return SamplingCadence(
      rawValue: UserDefaults.standard.double(forKey: key))
      ?? .twoSeconds
  }

  private static func fileTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: .now)
  }
}

enum ExportFormat {
  case json
  case csv

  var fileExtension: String {
    switch self {
    case .json: "json"
    case .csv: "csv"
    }
  }

  var contentType: UTType {
    switch self {
    case .json: .json
    case .csv: .commaSeparatedText
    }
  }
}
