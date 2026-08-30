import Foundation

public struct SystemInfoProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "system.overview",
    name: "System",
    category: .system,
    source: "Foundation ProcessInfo",
    capability: .publicAPI
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let info = ProcessInfo.processInfo
    #if arch(arm64)
      let architecture = "Apple Silicon (arm64)"
    #elseif arch(x86_64)
      let architecture = "Intel (x86_64)"
    #else
      let architecture = "Unknown"
    #endif

    let memory = UInt64(info.physicalMemory)
    let uptime = info.systemUptime
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "\(architecture) • \(SensorFormatting.bytes(memory)) memory",
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: [
        SensorChannel(id: "architecture", label: "Architecture", formattedValue: architecture),
        SensorChannel(
          id: "logical_processors", label: "Logical processors", value: Double(info.processorCount),
          formattedValue: "\(info.processorCount)"),
        SensorChannel(
          id: "active_processors", label: "Active processors",
          value: Double(info.activeProcessorCount), formattedValue: "\(info.activeProcessorCount)"),
        SensorChannel(
          id: "physical_memory", label: "Physical memory", value: Double(memory),
          formattedValue: SensorFormatting.bytes(memory), unit: "bytes"),
        SensorChannel(
          id: "os_version", label: "macOS", formattedValue: info.operatingSystemVersionString),
        SensorChannel(
          id: "uptime", label: "System uptime", value: uptime / 3600,
          formattedValue: SensorFormatting.decimal(uptime / 3600, fractionDigits: 1), unit: "hours",
          kind: .derived),
      ],
      notes: []
    )
  }
}
