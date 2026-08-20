import Foundation
import IOKit

enum GPUPerformanceValue {
  static func percentage(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (0...100).contains(value) else { return nil }
    return value
  }
}

public struct GPUPerformanceProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "system.gpu_performance",
    name: "GPU Performance",
    category: .system,
    source: "IOKit AGXAccelerator PerformanceStatistics",
    capability: .undocumented
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    guard let statistics = Self.readStatistics(), statistics.driverCount > 0 else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Apple GPU performance statistics were unavailable",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability,
        notes: [
          "Only a fixed allowlist of utilization and memory counters is requested; no device identity fields are read."
        ]
      )
    }

    var channels: [SensorChannel] = [
      SensorChannel(
        id: "gpu_driver_count",
        label: "GPU driver instances",
        value: Double(statistics.driverCount),
        formattedValue: "\(statistics.driverCount)"
      )
    ]
    if let utilization = statistics.deviceUtilization {
      channels.append(
        Self.percentageChannel(
          "gpu_device_utilization", "GPU device utilization", utilization))
    }
    if let utilization = statistics.rendererUtilization {
      channels.append(
        Self.percentageChannel(
          "gpu_renderer_utilization", "Renderer utilization", utilization))
    }
    if let utilization = statistics.tilerUtilization {
      channels.append(
        Self.percentageChannel("gpu_tiler_utilization", "Tiler utilization", utilization))
    }
    if let bytes = statistics.memoryInUse.value {
      channels.append(Self.byteChannel("gpu_memory_in_use", "GPU memory in use", bytes))
    }
    if let bytes = statistics.memoryAllocated.value {
      channels.append(Self.byteChannel("gpu_memory_allocated", "GPU memory allocated", bytes))
    }

    let summary =
      statistics.deviceUtilization.map {
        "GPU \(SensorFormatting.percentage($0))"
      } ?? "GPU memory counters available"
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
        "AGX PerformanceStatistics keys are undocumented and may change across macOS or GPU generations.",
        "Multiple driver instances use the maximum utilization and summed memory counters.",
        "Only fixed allowlisted counters are read; no registry names, IDs, or device identity fields are exported.",
      ]
    )
  }

  private struct Statistics {
    var driverCount = 0
    var deviceUtilization: Double?
    var rendererUtilization: Double?
    var tilerUtilization: Double?
    var memoryInUse = OptionalUInt64CounterAccumulator()
    var memoryAllocated = OptionalUInt64CounterAccumulator()
  }

  private static func readStatistics() -> Statistics? {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("AGXAccelerator"),
        &iterator
      ) == kIOReturnSuccess
    else { return nil }
    defer { IOObjectRelease(iterator) }

    var result = Statistics()
    var service = IOIteratorNext(iterator)
    while service != 0 {
      defer {
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
      }
      guard
        let unmanaged = IORegistryEntryCreateCFProperty(
          service,
          "PerformanceStatistics" as CFString,
          kCFAllocatorDefault,
          0
        ),
        let values = unmanaged.takeRetainedValue() as? [String: Any]
      else { continue }

      let device = GPUPerformanceValue.percentage(
        (values["Device Utilization %"] as? NSNumber)?.doubleValue)
      let renderer = GPUPerformanceValue.percentage(
        (values["Renderer Utilization %"] as? NSNumber)?.doubleValue)
      let tiler = GPUPerformanceValue.percentage(
        (values["Tiler Utilization %"] as? NSNumber)?.doubleValue)
      let memoryInUse = SensorNumericSafety.uint64(
        values["In use system memory"] as? NSNumber
      )
      let memoryAllocated = SensorNumericSafety.uint64(
        values["Alloc system memory"] as? NSNumber
      )
      guard
        [device, renderer, tiler].contains(where: { $0 != nil })
          || memoryInUse != nil || memoryAllocated != nil
      else { continue }

      result.driverCount += 1
      if let device {
        result.deviceUtilization = max(result.deviceUtilization ?? device, device)
      }
      if let renderer {
        result.rendererUtilization = max(result.rendererUtilization ?? renderer, renderer)
      }
      if let tiler {
        result.tilerUtilization = max(result.tilerUtilization ?? tiler, tiler)
      }
      result.memoryInUse.add(memoryInUse)
      result.memoryAllocated.add(memoryAllocated)
    }
    return result
  }

  private static func percentageChannel(
    _ id: String, _ label: String, _ value: Double
  ) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: value,
      formattedValue: SensorFormatting.percentage(value),
      unit: "%"
    )
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
}
