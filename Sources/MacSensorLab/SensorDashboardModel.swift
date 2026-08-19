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
  var displayName: String { "Every \(Int(rawValue)) seconds" }
  var shortLabel: String { "\(Int(rawValue)) s" }
}

struct SensorHistoryPoint: Identifiable {
  let id = UUID()
  let timestamp: Date
  let value: Double
}

@MainActor
final class SensorDashboardModel: ObservableObject {
  @Published var selection: DashboardSection? = .overview
  @Published var samplingCadence: SamplingCadence = .twoSeconds
  @Published private(set) var snapshots: [SensorSnapshot]
  @Published private(set) var history: [String: [SensorHistoryPoint]] = [:]
  @Published private(set) var isRefreshing = false
  @Published private(set) var isSamplingPaused = false
  @Published private(set) var lastRefreshDate: Date?
  @Published private(set) var recordingFileName: String?
  @Published private(set) var recordingProgress: SensorCSVRecordingProgress?
  @Published var lastActionMessage: String?

  private let providers: [any SensorProvider]
  private let maximumHistoryPoints = 600
  private var recorder: SensorCSVRecorder?
  private var lastRecordedMarkers: [String: RecordingMarker] = [:]

  private struct RecordingMarker: Equatable {
    let timestamp: Date
    let status: SensorStatus
  }

  var isRecording: Bool { recordingFileName != nil }

  init(providers: [any SensorProvider] = SensorProviderRegistry.providers()) {
    self.providers = providers
    self.snapshots = providers.map { SensorSnapshot.loading(metadata: $0.metadata) }
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
        if let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
          snapshots[index] = snapshot
        } else {
          snapshots.append(snapshot)
        }
        appendHistory(snapshot)
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
      lastRecordedMarkers.removeAll(keepingCapacity: true)
      lastActionMessage = "Started recording \(url.lastPathComponent)"
      Task { await appendRecordingBatch() }
    } catch {
      lastActionMessage = "Could not start recording: \(error.localizedDescription)"
    }
  }

  func stopRecording() async {
    guard let activeRecorder = recorder else { return }
    recorder = nil
    let fileName = recordingFileName ?? activeRecorder.destinationURL.lastPathComponent
    recordingFileName = nil
    lastRecordedMarkers.removeAll(keepingCapacity: true)

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
    let batch = snapshots.filter { snapshot in
      lastRecordedMarkers[snapshot.id]
        != RecordingMarker(timestamp: snapshot.timestamp, status: snapshot.status)
    }
    guard !batch.isEmpty else { return }

    do {
      let progress = try await activeRecorder.append(batch)
      guard recorder === activeRecorder else { return }
      for snapshot in batch {
        lastRecordedMarkers[snapshot.id] = RecordingMarker(
          timestamp: snapshot.timestamp, status: snapshot.status)
      }
      recordingProgress = progress
    } catch {
      guard recorder === activeRecorder else { return }
      recorder = nil
      recordingFileName = nil
      lastRecordedMarkers.removeAll(keepingCapacity: true)
      let progress = try? await activeRecorder.finish()
      if let progress { recordingProgress = progress }
      lastActionMessage = "Recording stopped safely: \(error.localizedDescription)"
    }
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
