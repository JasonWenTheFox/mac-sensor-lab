import Darwin
import Foundation

struct CPUTickSample: Equatable {
  let user: UInt64
  let system: UInt64
  let idle: UInt64
  let nice: UInt64

  var active: UInt64 { user + system + nice }
  var total: UInt64 { active + idle }
}

enum CPUUsageCalculator {
  static func percentage(previous: CPUTickSample, current: CPUTickSample) -> Double? {
    guard current.active >= previous.active, current.total >= previous.total else { return nil }
    let activeDelta = current.active - previous.active
    let totalDelta = current.total - previous.total
    guard totalDelta > 0 else { return nil }
    return min(max(Double(activeDelta) / Double(totalDelta) * 100, 0), 100)
  }
}

public final class SystemPerformanceProvider: SensorProvider, @unchecked Sendable {
  public let metadata = SensorProviderMetadata(
    id: "system.performance",
    name: "Performance",
    category: .system,
    source: "Mach host statistics, getloadavg, and sysctl",
    capability: .publicAPI
  )

  private let lock = NSLock()
  private var previousCPUTicks: CPUTickSample?

  public init() {}

  public func read() async -> SensorSnapshot {
    let currentTicks = Self.readCPUTicks()
    let cpuPercentage = lock.withLock { () -> Double? in
      defer { if let currentTicks { previousCPUTicks = currentTicks } }
      guard let previousCPUTicks, let currentTicks else { return nil }
      return CPUUsageCalculator.percentage(previous: previousCPUTicks, current: currentTicks)
    }

    var channels: [SensorChannel] = []
    if let cpuPercentage {
      channels.append(
        SensorChannel(
          id: "cpu_utilization",
          label: "CPU utilization",
          value: cpuPercentage,
          formattedValue: SensorFormatting.percentage(cpuPercentage),
          unit: "%",
          kind: .derived,
          note: "Aggregate non-idle Mach CPU ticks between consecutive samples."
        ))
    }

    let loadAverages = Self.readLoadAverages()
    for (index, minutes) in [1, 5, 15].enumerated() where index < loadAverages.count {
      let value = loadAverages[index]
      channels.append(
        SensorChannel(
          id: "load_average_\(minutes)m",
          label: "Load average (\(minutes) min)",
          value: value,
          formattedValue: SensorFormatting.decimal(value, fractionDigits: 2),
          kind: .raw,
          note: "Average number of processes in the system run queue; not CPU percent."
        ))
    }

    if let memory = Self.readMemoryStatistics() {
      channels += [
        Self.byteChannel("memory_free", "Free memory", memory.free),
        Self.byteChannel("memory_active", "Active memory", memory.active),
        Self.byteChannel("memory_inactive", "Inactive memory", memory.inactive),
        Self.byteChannel("memory_wired", "Wired memory", memory.wired),
        Self.byteChannel("memory_compressed", "Compressed memory", memory.compressed),
      ]
    }

    if let swap = Self.readSwapUsage() {
      channels += [
        Self.byteChannel("swap_used", "Swap used", swap.used),
        Self.byteChannel("swap_total", "Swap total", swap.total),
        SensorChannel(
          id: "swap_encrypted",
          label: "Swap encrypted",
          value: swap.encrypted ? 1 : 0,
          formattedValue: swap.encrypted ? "Yes" : "No"
        ),
      ]
    }

    guard !channels.isEmpty else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "System performance counters were unavailable",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability,
        notes: ["No process list or identifying information was requested."]
      )
    }

    let summary: String
    if let cpuPercentage {
      summary = "CPU \(SensorFormatting.percentage(cpuPercentage))"
    } else if let firstLoad = loadAverages.first {
      summary =
        "Collecting CPU baseline • load \(SensorFormatting.decimal(firstLoad, fractionDigits: 2))"
    } else {
      summary = "Memory and swap counters available"
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
        "CPU utilization needs two samples; the first read establishes a baseline.",
        "Memory channels are raw Mach page categories and may overlap conceptually with UI labels used by other tools.",
        "No process list or identifying information was requested.",
      ]
    )
  }

  private struct MemoryStatistics {
    let free: UInt64
    let active: UInt64
    let inactive: UInt64
    let wired: UInt64
    let compressed: UInt64
  }

  private struct SwapUsage {
    let used: UInt64
    let total: UInt64
    let encrypted: Bool
  }

  private static func readCPUTicks() -> CPUTickSample? {
    var processorCount: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    let result = host_processor_info(
      mach_host_self(),
      PROCESSOR_CPU_LOAD_INFO,
      &processorCount,
      &info,
      &infoCount
    )
    guard result == KERN_SUCCESS, let info else { return nil }
    defer {
      let byteCount = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
      vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), byteCount)
    }

    var sample = CPUTickSample(user: 0, system: 0, idle: 0, nice: 0)
    info.withMemoryRebound(
      to: processor_cpu_load_info_data_t.self,
      capacity: Int(processorCount)
    ) { pointer in
      for index in 0..<Int(processorCount) {
        let ticks = pointer[index].cpu_ticks
        sample = CPUTickSample(
          user: sample.user + UInt64(ticks.0),
          system: sample.system + UInt64(ticks.1),
          idle: sample.idle + UInt64(ticks.2),
          nice: sample.nice + UInt64(ticks.3)
        )
      }
    }
    return sample
  }

  private static func readLoadAverages() -> [Double] {
    var loads = [Double](repeating: 0, count: 3)
    let count = loads.withUnsafeMutableBufferPointer { buffer in
      getloadavg(buffer.baseAddress, Int32(buffer.count))
    }
    guard count > 0 else { return [] }
    return Array(loads.prefix(Int(count)))
  }

  private static func readMemoryStatistics() -> MemoryStatistics? {
    var statistics = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &statistics) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }

    var pageSize: vm_size_t = 0
    guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
    func bytes(_ pages: natural_t) -> UInt64 {
      UInt64(pages) * UInt64(pageSize)
    }
    return MemoryStatistics(
      free: bytes(statistics.free_count),
      active: bytes(statistics.active_count),
      inactive: bytes(statistics.inactive_count),
      wired: bytes(statistics.wire_count),
      compressed: bytes(statistics.compressor_page_count)
    )
  }

  private static func readSwapUsage() -> SwapUsage? {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
    return SwapUsage(
      used: usage.xsu_used,
      total: usage.xsu_total,
      encrypted: usage.xsu_encrypted != 0
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
