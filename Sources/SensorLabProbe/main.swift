import Darwin
import Foundation
import SensorCore

@main
struct SensorLabProbe {
  static func main() async {
    let snapshots = await SensorProviderRegistry.readAll()
    do {
      let data = try SensorExportService.jsonData(snapshots)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      FileHandle.standardError.write(Data("sensorlab-probe: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }
}
