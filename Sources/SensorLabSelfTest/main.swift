import Darwin
import Foundation
import SensorCore

@main
struct SensorLabSelfTest {
  static func main() async {
    var failures: [String] = []
    let portableMode = CommandLine.arguments.contains("--portable")
    let spuStabilityMode = CommandLine.arguments.contains("--spu-stability")
    let providers = SensorProviderRegistry.providers()

    if providers.count < 14 {
      failures.append("expected at least 14 providers, found \(providers.count)")
    }

    let snapshots = await SensorProviderRegistry.readAll()
    if snapshots.count != providers.count {
      failures.append(
        "snapshot count \(snapshots.count) does not match provider count \(providers.count)")
    }
    let minimumAvailable = portableMode ? 3 : 5
    if snapshots.filter({ $0.status == .available }).count < minimumAvailable {
      failures.append("fewer than \(minimumAvailable) providers returned real available data")
    }

    failures += SensorContractAudit.issues(
      providers: providers,
      snapshots: snapshots
    ).map(\.description)

    if let lid = snapshots.first(where: { $0.id == "motion.lid_angle" }),
      lid.status == .available,
      let value = lid.channels.first(where: { $0.id == "angle" })?.value,
      !(0...360).contains(value)
    {
      failures.append("lid angle is out of range: \(value)")
    }

    for channel in snapshots.flatMap(\.channels) {
      if channel.unit == "°C", let value = channel.value, !(-20...110).contains(value) {
        failures.append("temperature is out of range: \(channel.id)=\(value)")
      }
      if channel.unit == "RPM", let value = channel.value, !(0...20_000).contains(value) {
        failures.append("fan speed is out of range: \(channel.id)=\(value)")
      }
      if channel.id.hasPrefix("acceleration_"), let value = channel.value,
        !(-64...64).contains(value)
      {
        failures.append("acceleration is out of expected range: \(channel.id)=\(value)")
      }
      if ["level_roll", "level_pitch"].contains(channel.id), let value = channel.value,
        !(-180...180).contains(value)
      {
        failures.append("derived angle is out of range: \(channel.id)=\(value)")
      }
      if channel.id == "cpu_utilization", let value = channel.value, !(0...100).contains(value) {
        failures.append("CPU utilization is out of range: \(value)")
      }
      if channel.id.hasPrefix("gpu_") && channel.id.hasSuffix("_utilization"),
        let value = channel.value, !(0...100).contains(value)
      {
        failures.append("GPU utilization is out of range: \(channel.id)=\(value)")
      }
    }

    if !portableMode {
      let performanceProvider = SystemPerformanceProvider()
      _ = await performanceProvider.read()
      try? await Task.sleep(for: .milliseconds(150))
      let performance = await performanceProvider.read()
      if performance.channels.first(where: { $0.id == "cpu_utilization" })?.value == nil {
        failures.append("performance provider did not produce CPU utilization after a baseline")
      }

      let networkProvider = NetworkThroughputProvider()
      _ = await networkProvider.read()
      try? await Task.sleep(for: .milliseconds(150))
      let network = await networkProvider.read()
      if network.channels.first(where: { $0.id == "network_receive_rate" })?.value == nil {
        failures.append("network provider did not produce throughput after a baseline")
      }

      let diskProvider = DiskIOProvider()
      _ = await diskProvider.read()
      try? await Task.sleep(for: .milliseconds(150))
      let disk = await diskProvider.read()
      if disk.channels.first(where: { $0.id == "disk_read_rate" })?.value == nil {
        failures.append("disk provider did not produce throughput after a baseline")
      }
    }

    do {
      let json = try SensorExportService.jsonData(snapshots)
      _ = try JSONSerialization.jsonObject(with: json)
      let diagnostics = try SensorDiagnosticsExportService.jsonData(
        snapshots,
        applicationVersion: "self-test"
      )
      _ = try JSONSerialization.jsonObject(with: diagnostics)
      let diagnosticText = String(decoding: diagnostics, as: UTF8.self)
      let forbiddenDiagnosticKeys = [
        "value", "formattedValue", "summary", "notes", "source", "timestamp", "name",
        "label",
      ]
      for key in forbiddenDiagnosticKeys where diagnosticText.contains("\"\(key)\"") {
        failures.append("diagnostics report contains forbidden key: \(key)")
      }
    } catch {
      failures.append("JSON export is invalid: \(error.localizedDescription)")
    }

    let csv = SensorExportService.csvData(snapshots)
    if !String(decoding: csv, as: UTF8.self).hasPrefix("provider_id,") {
      failures.append("CSV export header is invalid")
    }

    var spuStabilitySummary: String?
    if spuStabilityMode {
      let result = await checkSPUStability(attempts: 20)
      failures += result.failures
      spuStabilitySummary = result.summary
    }

    if failures.isEmpty {
      let mode = portableMode ? "portable" : "hardware"
      print(
        "PASS (\(mode)): \(snapshots.count) providers; \(snapshots.filter { $0.status == .available }.count) available; JSON/CSV and privacy checks succeeded"
      )
      if let spuStabilitySummary { print(spuStabilitySummary) }
      exit(EXIT_SUCCESS)
    }

    for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
    exit(EXIT_FAILURE)
  }

  private static func checkSPUStability(attempts: Int) async -> (
    failures: [String], summary: String
  ) {
    let provider = SPULiveProvider()
    var failures: [String] = []
    var counts: [String: Int] = [:]
    var liveSamples = 0
    var cachedSamples = 0

    for _ in 0..<attempts {
      let snapshot = await provider.read()
      counts[snapshot.status.rawValue, default: 0] += 1
      if snapshot.status == .available { liveSamples += 1 }
      if snapshot.status == .degraded, !snapshot.channels.isEmpty { cachedSamples += 1 }
      if snapshot.status == .permissionRequired {
        failures.append(
          "SPU access was classified as permission-required during a sequential stability run")
      }
      for channel in snapshot.channels {
        if let value = channel.value, !value.isFinite {
          failures.append("SPU stability run returned a non-finite value: \(channel.id)")
        }
      }
    }

    if liveSamples == 0 {
      failures.append("SPU stability run never received a live report")
    }

    let statuses = counts.keys.sorted().map {
      "\($0)=\(counts[$0, default: 0])"
    }.joined(separator: ", ")
    let summary =
      "SPU stability: \(attempts) reads; \(liveSamples) live; \(cachedSamples) recent-sample fallbacks; \(statuses)"
    return (failures, summary)
  }
}
