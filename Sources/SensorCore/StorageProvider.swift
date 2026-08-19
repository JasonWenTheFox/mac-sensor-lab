import Foundation

public struct StorageProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "storage.system_volume",
    name: "Storage",
    category: .storage,
    source: "Foundation FileManager",
    capability: .publicAPI
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    do {
      let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
      let total = (attributes[.systemSize] as? NSNumber)?.uint64Value ?? 0
      let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
      let used = total >= free ? total - free : 0
      let usedPercent = total > 0 ? Double(used) / Double(total) * 100 : 0

      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "\(SensorFormatting.bytes(free)) available",
        status: .available,
        source: metadata.source,
        capability: metadata.capability,
        channels: [
          SensorChannel(
            id: "total", label: "Capacity", value: Double(total),
            formattedValue: SensorFormatting.bytes(total), unit: "bytes"),
          SensorChannel(
            id: "available", label: "Available", value: Double(free),
            formattedValue: SensorFormatting.bytes(free), unit: "bytes"),
          SensorChannel(
            id: "used", label: "Used", value: Double(used),
            formattedValue: SensorFormatting.bytes(used), unit: "bytes", kind: .derived),
          SensorChannel(
            id: "used_percent", label: "Used", value: usedPercent,
            formattedValue: SensorFormatting.percentage(usedPercent), unit: "%", kind: .derived),
        ]
      )
    } catch {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Could not read the system volume",
        status: .error,
        source: metadata.source,
        capability: metadata.capability,
        notes: [error.localizedDescription]
      )
    }
  }
}
