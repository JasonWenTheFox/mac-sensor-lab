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

struct SensorHistoryPoint: Identifiable {
  let id = UUID()
  let timestamp: Date
  let value: Double
}

@MainActor
final class SensorDashboardModel: ObservableObject {
  @Published var selection: DashboardSection? = .overview
  @Published private(set) var snapshots: [SensorSnapshot]
  @Published private(set) var history: [String: [SensorHistoryPoint]] = [:]
  @Published private(set) var isRefreshing = false
  @Published var lastExportMessage: String?

  private let providers: [any SensorProvider]

  init(providers: [any SensorProvider] = SensorProviderRegistry.providers()) {
    self.providers = providers
    self.snapshots = providers.map { SensorSnapshot.loading(metadata: $0.metadata) }
  }

  func runLiveUpdates() async {
    await refresh()
    while !Task.isCancelled {
      do {
        try await Task.sleep(for: .seconds(2))
      } catch {
        return
      }
      await refresh()
    }
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
  }

  private func appendHistory(_ snapshot: SensorSnapshot) {
    for channel in snapshot.channels {
      guard let value = channel.value, value.isFinite else { continue }
      let key = "\(snapshot.id)/\(channel.id)"
      var points = history[key, default: []]
      guard points.last?.timestamp != snapshot.timestamp else { continue }
      points.append(SensorHistoryPoint(timestamp: snapshot.timestamp, value: value))
      if points.count > 60 { points.removeFirst(points.count - 60) }
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
      lastExportMessage = "Exported \(url.lastPathComponent)"
    } catch {
      lastExportMessage = "Export failed: \(error.localizedDescription)"
    }
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
