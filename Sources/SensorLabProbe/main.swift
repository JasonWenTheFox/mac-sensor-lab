import Darwin
import Foundation
import SensorCore

@main
struct SensorLabProbe {
  static func main() async {
    let arguments = CommandLine.arguments.dropFirst().filter { $0 != "--" }
    if arguments.contains("--help") || arguments.contains("-h") {
      printHelp()
      exit(EXIT_SUCCESS)
    }
    let supported = Set(["--demo", "--diagnostics"])
    let unknown = arguments.filter { !supported.contains($0) }
    guard unknown.isEmpty else {
      FileHandle.standardError.write(
        Data("sensorlab-probe: unknown option \(unknown[0]); use --help\n".utf8))
      exit(EXIT_FAILURE)
    }

    let isDemo = arguments.contains("--demo")
    let providers =
      isDemo ? SensorDemoProviderRegistry.providers() : SensorProviderRegistry.providers()
    let snapshots = await SensorProviderRegistry.readAll(providers)
    do {
      let data =
        if arguments.contains("--diagnostics") {
          try SensorDiagnosticsExportService.jsonData(
            snapshots,
            applicationVersion: "sensorlab-probe\(isDemo ? " demo" : "")"
          )
        } else {
          try SensorExportService.jsonData(snapshots)
        }
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      FileHandle.standardError.write(Data("sensorlab-probe: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  private static func printHelp() {
    print(
      """
      Usage: sensorlab-probe [--demo] [--diagnostics]

        --demo         Use deterministic built-in fixtures instead of hardware.
        --diagnostics  Omit readings and free text; output privacy-safe provider metadata.
        --help, -h     Show this help.

      Without options, the probe reads live providers and outputs a full JSON snapshot locally.
      """)
  }
}
