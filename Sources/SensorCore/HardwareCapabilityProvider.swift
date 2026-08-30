import Foundation

public struct HardwareCapabilityProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "diagnostics.hardware_capabilities",
    name: "Experimental Hardware",
    category: .diagnostics,
    source: "IOKit service discovery",
    capability: .undocumented
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let capabilities: [(String, String, String)] = [
      ("apple_smc", "Apple SMC", "AppleSMC"),
      ("force_touch", "Force Touch trackpad", "AppleMultitouchTrackpadHIDEventDriver"),
      ("smart_battery", "Smart battery", "AppleSmartBattery"),
    ]
    let channels = capabilities.map { id, label, className in
      let count = IOKitHelpers.serviceCount(className)
      return SensorChannel(
        id: id,
        label: label,
        value: Double(count),
        formattedValue: count > 0 ? "Detected" : "Not detected",
        note: count > 0 ? "Hardware/service presence only." : nil
      )
    }
    let detected = channels.filter { ($0.value ?? 0) > 0 }.count

    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "\(detected) of \(channels.count) capabilities detected",
      status: detected > 0 ? .degraded : .unavailable,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: []
    )
  }
}
