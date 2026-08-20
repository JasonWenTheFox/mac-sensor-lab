import Foundation

struct PublicStorageCapacityReading: Equatable, Sendable {
  let total: UInt64?
  let available: UInt64?
  let availableForImportantUsage: UInt64?
  let availableForOpportunisticUsage: UInt64?
}

enum PublicStorageCapacityMeasurements {
  static func bytes(_ value: Int?) -> UInt64? {
    guard let value, value >= 0 else { return nil }
    return UInt64(value)
  }

  static func bytes(_ value: Int64?) -> UInt64? {
    guard let value, value >= 0 else { return nil }
    return UInt64(value)
  }

  static func boundedAvailable(_ value: UInt64?, total: UInt64?) -> UInt64? {
    guard let value, let total, total > 0, value <= total else { return nil }
    return value
  }

  static func used(total: UInt64?, available: UInt64?) -> UInt64? {
    guard let total, total > 0,
      let available = boundedAvailable(available, total: total)
    else { return nil }
    return total - available
  }

  static func usedPercentage(total: UInt64?, available: UInt64?) -> Double? {
    guard let total, let used = used(total: total, available: available) else { return nil }
    let percentage = Double(used) / Double(total) * 100
    guard percentage.isFinite, (0...100).contains(percentage) else { return nil }
    return percentage
  }
}

public struct StorageProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "storage.system_volume",
    name: "Storage",
    category: .storage,
    source: "Foundation URLResourceValues",
    capability: .publicAPI
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    do {
      let values = try URL(fileURLWithPath: "/", isDirectory: true).resourceValues(
        forKeys: [
          .volumeTotalCapacityKey,
          .volumeAvailableCapacityKey,
          .volumeAvailableCapacityForImportantUsageKey,
          .volumeAvailableCapacityForOpportunisticUsageKey,
        ]
      )
      return snapshot(
        reading: PublicStorageCapacityReading(
          total: PublicStorageCapacityMeasurements.bytes(values.volumeTotalCapacity),
          available: PublicStorageCapacityMeasurements.bytes(values.volumeAvailableCapacity),
          availableForImportantUsage: PublicStorageCapacityMeasurements.bytes(
            values.volumeAvailableCapacityForImportantUsage
          ),
          availableForOpportunisticUsage: PublicStorageCapacityMeasurements.bytes(
            values.volumeAvailableCapacityForOpportunisticUsage
          )
        )
      )
    } catch {
      return unavailableSnapshot()
    }
  }

  func snapshot(reading: PublicStorageCapacityReading) -> SensorSnapshot {
    guard let total = reading.total, total > 0 else { return unavailableSnapshot() }
    let available = PublicStorageCapacityMeasurements.boundedAvailable(
      reading.available,
      total: total
    )
    let important = PublicStorageCapacityMeasurements.boundedAvailable(
      reading.availableForImportantUsage,
      total: total
    )
    let opportunistic = PublicStorageCapacityMeasurements.boundedAvailable(
      reading.availableForOpportunisticUsage,
      total: total
    )

    var channels = [byteChannel(id: "total", label: "Capacity", value: total)]
    if let available {
      channels.append(byteChannel(id: "available", label: "Available", value: available))
    }
    if let important {
      channels.append(
        byteChannel(
          id: "available_important",
          label: "Available for important usage",
          value: important,
          note: "Foundation estimate that may include purgeable space for important usage."
        )
      )
    }
    if let opportunistic {
      channels.append(
        byteChannel(
          id: "available_opportunistic",
          label: "Available for opportunistic usage",
          value: opportunistic,
          note:
            "Foundation estimate for nonessential work; it can be lower than ordinary free space."
        )
      )
    }
    if let used = PublicStorageCapacityMeasurements.used(total: total, available: available) {
      channels.append(byteChannel(id: "used", label: "Used", value: used, kind: .derived))
    }
    if let usedPercentage = PublicStorageCapacityMeasurements.usedPercentage(
      total: total,
      available: available
    ) {
      channels.append(
        SensorChannel(
          id: "used_percent",
          label: "Used",
          value: usedPercentage,
          formattedValue: SensorFormatting.percentage(usedPercentage),
          unit: "%",
          kind: .derived
        )
      )
    }

    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: available.map { "\(SensorFormatting.bytes($0)) available" }
        ?? "Storage capacity available",
      status: available == nil ? .degraded : .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: [
        "Capacity semantics come from public Foundation volume resource keys.",
        "Volume names, identifiers, mount paths, and system error text are intentionally omitted.",
      ]
    )
  }

  private func unavailableSnapshot() -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "Could not read system-volume capacity",
      status: .unavailable,
      source: metadata.source,
      capability: metadata.capability,
      notes: ["No volume path or system error text is exported."]
    )
  }

  private func byteChannel(
    id: String,
    label: String,
    value: UInt64,
    kind: SensorValueKind = .raw,
    note: String? = nil
  ) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: Double(value),
      formattedValue: SensorFormatting.bytes(value),
      unit: "bytes",
      kind: kind,
      note: note
    )
  }
}
