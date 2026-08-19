import Foundation
import IOKit

struct DiskIOCounterSample: Equatable {
  let bytesRead: UInt64
  let bytesWritten: UInt64
  let readOperations: UInt64
  let writeOperations: UInt64
  let timestamp: TimeInterval
}

struct DiskIORates: Equatable {
  let readBytesPerSecond: Double
  let writeBytesPerSecond: Double
  let readOperationsPerSecond: Double
  let writeOperationsPerSecond: Double
}

enum DiskIORateCalculator {
  static func rates(previous: DiskIOCounterSample, current: DiskIOCounterSample) -> DiskIORates? {
    let elapsed = current.timestamp - previous.timestamp
    guard elapsed > 0,
      current.bytesRead >= previous.bytesRead,
      current.bytesWritten >= previous.bytesWritten,
      current.readOperations >= previous.readOperations,
      current.writeOperations >= previous.writeOperations
    else { return nil }

    return DiskIORates(
      readBytesPerSecond: Double(current.bytesRead - previous.bytesRead) / elapsed,
      writeBytesPerSecond: Double(current.bytesWritten - previous.bytesWritten) / elapsed,
      readOperationsPerSecond: Double(current.readOperations - previous.readOperations) / elapsed,
      writeOperationsPerSecond: Double(current.writeOperations - previous.writeOperations)
        / elapsed
    )
  }
}

public final class DiskIOProvider: SensorProvider, @unchecked Sendable {
  public let metadata = SensorProviderMetadata(
    id: "storage.disk_io",
    name: "Disk Activity",
    category: .storage,
    source: "IOKit IOBlockStorageDriver statistics",
    capability: .publicAPI
  )

  private let lock = NSLock()
  private var previousSample: DiskIOCounterSample?

  public init() {}

  public func read() async -> SensorSnapshot {
    guard let aggregate = Self.readAggregateCounters(), aggregate.deviceCount > 0 else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Block-storage statistics were unavailable",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability,
        notes: ["No device names, serial numbers, volume names, or file paths are read."]
      )
    }

    let current = DiskIOCounterSample(
      bytesRead: aggregate.bytesRead,
      bytesWritten: aggregate.bytesWritten,
      readOperations: aggregate.readOperations,
      writeOperations: aggregate.writeOperations,
      timestamp: ProcessInfo.processInfo.systemUptime
    )
    let rates = lock.withLock { () -> DiskIORates? in
      defer { previousSample = current }
      guard let previousSample else { return nil }
      return DiskIORateCalculator.rates(previous: previousSample, current: current)
    }

    var channels = [
      SensorChannel(
        id: "disk_device_count",
        label: "Aggregated block devices",
        value: Double(aggregate.deviceCount),
        formattedValue: "\(aggregate.deviceCount)"
      ),
      Self.byteChannel("disk_bytes_read_total", "Read total", aggregate.bytesRead),
      Self.byteChannel("disk_bytes_written_total", "Written total", aggregate.bytesWritten),
      SensorChannel(
        id: "disk_read_operations_total",
        label: "Read operations",
        value: Double(aggregate.readOperations),
        formattedValue: "\(aggregate.readOperations)"
      ),
      SensorChannel(
        id: "disk_write_operations_total",
        label: "Write operations",
        value: Double(aggregate.writeOperations),
        formattedValue: "\(aggregate.writeOperations)"
      ),
      SensorChannel(
        id: "disk_read_errors_total",
        label: "Read errors",
        value: Double(aggregate.readErrors),
        formattedValue: "\(aggregate.readErrors)"
      ),
      SensorChannel(
        id: "disk_write_errors_total",
        label: "Write errors",
        value: Double(aggregate.writeErrors),
        formattedValue: "\(aggregate.writeErrors)"
      ),
    ]

    if let rates {
      channels += [
        Self.rateChannel("disk_read_rate", "Read rate", rates.readBytesPerSecond),
        Self.rateChannel("disk_write_rate", "Write rate", rates.writeBytesPerSecond),
        SensorChannel(
          id: "disk_read_operation_rate",
          label: "Read operation rate",
          value: rates.readOperationsPerSecond,
          formattedValue: SensorFormatting.decimal(
            rates.readOperationsPerSecond, fractionDigits: 1),
          unit: "operations/s",
          kind: .derived
        ),
        SensorChannel(
          id: "disk_write_operation_rate",
          label: "Write operation rate",
          value: rates.writeOperationsPerSecond,
          formattedValue: SensorFormatting.decimal(
            rates.writeOperationsPerSecond, fractionDigits: 1),
          unit: "operations/s",
          kind: .derived
        ),
      ]
    }

    let summary =
      if let rates {
        "Read \(SensorFormatting.bytesPerSecond(rates.readBytesPerSecond)) • Write \(SensorFormatting.bytesPerSecond(rates.writeBytesPerSecond))"
      } else {
        "Collecting activity baseline • \(aggregate.deviceCount) block devices"
      }

    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: [
        "Rates need two samples; a counter reset or device change starts a new baseline.",
        "Totals are driver-lifetime counters aggregated across block-storage drivers.",
        "No device names, serial numbers, volume names, or file paths are read or exported.",
      ]
    )
  }

  private struct AggregateCounters {
    var deviceCount = 0
    var bytesRead: UInt64 = 0
    var bytesWritten: UInt64 = 0
    var readOperations: UInt64 = 0
    var writeOperations: UInt64 = 0
    var readErrors: UInt64 = 0
    var writeErrors: UInt64 = 0
  }

  private static func readAggregateCounters() -> AggregateCounters? {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("IOBlockStorageDriver"),
        &iterator
      ) == kIOReturnSuccess
    else { return nil }
    defer { IOObjectRelease(iterator) }

    var aggregate = AggregateCounters()
    var service = IOIteratorNext(iterator)
    while service != 0 {
      defer {
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
      }
      guard
        let unmanaged = IORegistryEntryCreateCFProperty(
          service,
          "Statistics" as CFString,
          kCFAllocatorDefault,
          0
        ),
        let statistics = unmanaged.takeRetainedValue() as? [String: Any],
        let bytesRead = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value,
        let bytesWritten = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value,
        let readOperations = (statistics["Operations (Read)"] as? NSNumber)?.uint64Value,
        let writeOperations = (statistics["Operations (Write)"] as? NSNumber)?.uint64Value
      else { continue }

      aggregate.deviceCount += 1
      aggregate.bytesRead = saturatingSum(aggregate.bytesRead, bytesRead)
      aggregate.bytesWritten = saturatingSum(aggregate.bytesWritten, bytesWritten)
      aggregate.readOperations = saturatingSum(aggregate.readOperations, readOperations)
      aggregate.writeOperations = saturatingSum(aggregate.writeOperations, writeOperations)
      aggregate.readErrors = saturatingSum(
        aggregate.readErrors,
        (statistics["Errors (Read)"] as? NSNumber)?.uint64Value ?? 0
      )
      aggregate.writeErrors = saturatingSum(
        aggregate.writeErrors,
        (statistics["Errors (Write)"] as? NSNumber)?.uint64Value ?? 0
      )
    }
    return aggregate
  }

  private static func saturatingSum(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? .max : result.partialValue
  }

  private static func byteChannel(_ id: String, _ label: String, _ value: UInt64) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: Double(value),
      formattedValue: SensorFormatting.bytes(value),
      unit: "bytes"
    )
  }

  private static func rateChannel(_ id: String, _ label: String, _ value: Double) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: value,
      formattedValue: SensorFormatting.bytesPerSecond(value),
      unit: "bytes/s",
      kind: .derived
    )
  }
}
