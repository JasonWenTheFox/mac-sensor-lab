import Darwin
import Foundation
import SensorCore

@main
struct SensorLabSelfTest {
  static func main() async {
    var failures: [String] = []
    let portableMode = CommandLine.arguments.contains("--portable")
    let providers = SensorProviderRegistry.providers()
    let providerIDs = providers.map(\.metadata.id)

    if Set(providerIDs).count != providerIDs.count {
      failures.append("provider IDs are not unique")
    }
    if providers.count < 9 {
      failures.append("expected at least 9 providers, found \(providers.count)")
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

    let forbiddenIDs = ["serial", "uuid", "udid", "username", "hostname", "ssid", "bssid"]
    for snapshot in snapshots {
      let allIDs = [snapshot.id] + snapshot.channels.map(\.id)
      for id in allIDs
      where forbiddenIDs.contains(where: { id.localizedCaseInsensitiveContains($0) }) {
        failures.append("forbidden identifying field ID exported: \(id)")
      }
    }

    if let lid = snapshots.first(where: { $0.id == "motion.lid_angle" }),
      lid.status == .available,
      let value = lid.channels.first(where: { $0.id == "angle" })?.value,
      !(0...360).contains(value)
    {
      failures.append("lid angle is out of range: \(value)")
    }

    for channel in snapshots.flatMap(\.channels) {
      if let value = channel.value, !value.isFinite {
        failures.append("non-finite value: \(channel.id)")
      }
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
    }

    do {
      let json = try SensorExportService.jsonData(snapshots)
      _ = try JSONSerialization.jsonObject(with: json)
    } catch {
      failures.append("JSON export is invalid: \(error.localizedDescription)")
    }

    let csv = SensorExportService.csvData(snapshots)
    if !String(decoding: csv, as: UTF8.self).hasPrefix("provider_id,") {
      failures.append("CSV export header is invalid")
    }

    if failures.isEmpty {
      let mode = portableMode ? "portable" : "hardware"
      print(
        "PASS (\(mode)): \(snapshots.count) providers; \(snapshots.filter { $0.status == .available }.count) available; JSON/CSV and privacy checks succeeded"
      )
      exit(EXIT_SUCCESS)
    }

    for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
    exit(EXIT_FAILURE)
  }
}
