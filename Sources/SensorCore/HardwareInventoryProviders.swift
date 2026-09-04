import Darwin
import Foundation
import LocalAuthentication
import Metal

enum HardwareInventorySanitizer {
  static func modelIdentifier(_ value: String?) -> String? {
    boundedASCII(value, maximumBytes: 64) { scalar in
      isASCIIAlphanumeric(scalar) || scalar == ","
    }
  }

  static func appleSoCName(_ value: String?) -> String? {
    guard
      let value = boundedASCII(
        value, maximumBytes: 64,
        allowed: { scalar in
          isASCIIAlphanumeric(scalar) || scalar == " " || scalar == "-"
        })
    else { return nil }
    let tokens = value.split(separator: " ").map(String.init)
    guard (2...3).contains(tokens.count), tokens[0] == "Apple" else { return nil }
    let generation = tokens[1]
    guard generation.first == "M",
      generation.dropFirst().count <= 2,
      !generation.dropFirst().isEmpty,
      generation.dropFirst().allSatisfy(\.isNumber)
    else { return nil }
    if tokens.count == 3, !["Pro", "Max", "Ultra"].contains(tokens[2]) { return nil }
    return value
  }

  static func displayName(_ value: String?) -> String? {
    boundedASCII(value, maximumBytes: 128) { scalar in
      scalar.value >= 0x20 && scalar.value <= 0x7E
    }
  }

  static func coreCount(_ value: Int?) -> Int? {
    guard let value, (1...256).contains(value) else { return nil }
    return value
  }

  private static func boundedASCII(
    _ candidate: String?,
    maximumBytes: Int,
    allowed: (Unicode.Scalar) -> Bool
  ) -> String? {
    guard let candidate,
      candidate == candidate.trimmingCharacters(in: .whitespacesAndNewlines),
      !candidate.isEmpty,
      candidate.utf8.count <= maximumBytes,
      candidate.unicodeScalars.allSatisfy({ $0.isASCII && allowed($0) })
    else { return nil }
    return candidate
  }

  private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
    let value = scalar.value
    return (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value)
  }
}

private enum HardwareSysctlReader {
  static func string(_ name: String) -> String? {
    var byteCount = 0
    guard sysctlbyname(name, nil, &byteCount, nil, 0) == 0,
      byteCount > 1,
      byteCount <= 256
    else { return nil }

    var bytes = [UInt8](repeating: 0, count: byteCount)
    let result = bytes.withUnsafeMutableBytes { buffer in
      sysctlbyname(name, buffer.baseAddress, &byteCount, nil, 0)
    }
    guard result == 0 else { return nil }
    let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
    return String(decoding: bytes[..<end], as: UTF8.self)
  }

  static func integer(_ name: String) -> Int? {
    var value: Int32 = 0
    var byteCount = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &byteCount, nil, 0) == 0,
      byteCount == MemoryLayout<Int32>.size
    else { return nil }
    return Int(value)
  }
}

private enum HardwareInventoryChannel {
  static func integer(_ id: String, _ label: String, _ value: Int) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: Double(value),
      formattedValue: String(value)
    )
  }

  static func boolean(_ id: String, _ label: String, _ value: Bool) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: value ? 1 : 0,
      formattedValue: value ? "Yes" : "No"
    )
  }

  static func bytes(_ id: String, _ label: String, _ value: UInt64) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: Double(value),
      formattedValue: SensorFormatting.bytes(value),
      unit: "bytes"
    )
  }
}

public struct HardwarePlatformProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "hardware.platform",
    name: "Mac Platform",
    category: .system,
    source: "Darwin sysctl model class",
    capability: .undocumented,
    domain: .system,
    accessLevel: .undocumentedOrdinary,
    compatibilityConfidence: .singleModelObserved
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    guard
      let modelIdentifier = HardwareInventorySanitizer.modelIdentifier(
        HardwareSysctlReader.string("hw.model")
      )
    else {
      return unavailableSnapshot(summary: "Mac model class was unavailable")
    }

    #if arch(arm64)
      let architecture = "arm64"
    #elseif arch(x86_64)
      let architecture = "x86_64"
    #else
      let architecture = "Unknown"
    #endif
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: modelIdentifier,
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: [
        SensorChannel(
          id: "model_identifier",
          label: "Model identifier",
          formattedValue: modelIdentifier,
          note: "A shared model-class identifier, not a unique device identifier."
        ),
        SensorChannel(
          id: "architecture",
          label: "Architecture",
          formattedValue: architecture
        ),
      ],
      notes: ["Serial numbers, hardware UUIDs, host names, and user names are not read."]
    )
  }

  private func unavailableSnapshot(summary: String) -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: .unavailable,
      source: metadata.source,
      capability: metadata.capability
    )
  }
}

public struct SoCHardwareProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "hardware.soc",
    name: "Apple SoC",
    category: .system,
    source: "Darwin sysctl CPU brand class",
    capability: .undocumented,
    domain: .soc,
    accessLevel: .undocumentedOrdinary,
    compatibilityConfidence: .singleModelObserved
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    guard
      let socName = HardwareInventorySanitizer.appleSoCName(
        HardwareSysctlReader.string("machdep.cpu.brand_string")
      )
    else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Apple SoC family was unavailable",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability,
        notes: ["This provider only accepts a bounded Apple M-series family name."]
      )
    }
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: socName,
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: [
        SensorChannel(
          id: "soc_name",
          label: "SoC family",
          formattedValue: socName,
          note: "A shared product-family name, not a chip identifier."
        )
      ]
    )
  }
}

public struct CPUHardwareProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "hardware.cpu",
    name: "CPU Topology",
    category: .system,
    source: "Darwin sysctl topology counters",
    capability: .undocumented,
    domain: .cpu,
    accessLevel: .undocumentedOrdinary,
    compatibilityConfidence: .singleModelObserved
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    guard
      let physical = HardwareInventorySanitizer.coreCount(
        HardwareSysctlReader.integer("hw.physicalcpu")
      ),
      let logical = HardwareInventorySanitizer.coreCount(
        HardwareSysctlReader.integer("hw.logicalcpu")
      ),
      logical >= physical
    else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "CPU topology was unavailable",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability
      )
    }

    var channels = [
      HardwareInventoryChannel.integer("physical_cores", "Physical CPU cores", physical),
      HardwareInventoryChannel.integer("logical_cores", "Logical CPU cores", logical),
    ]
    let performance = HardwareInventorySanitizer.coreCount(
      HardwareSysctlReader.integer("hw.perflevel0.physicalcpu")
    )
    let efficiency = HardwareInventorySanitizer.coreCount(
      HardwareSysctlReader.integer("hw.perflevel1.physicalcpu")
    )
    if let performance, let efficiency, performance + efficiency == physical {
      channels += [
        HardwareInventoryChannel.integer(
          "performance_cores", "Performance CPU cores", performance
        ),
        HardwareInventoryChannel.integer(
          "efficiency_cores", "Efficiency CPU cores", efficiency
        ),
      ]
    }
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "\(physical) physical • \(logical) logical cores",
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: [
        "Performance and efficiency counts appear only when both bounded counters agree with the physical total."
      ]
    )
  }
}

public struct MemoryHardwareProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "hardware.memory",
    name: "Memory Hardware",
    category: .system,
    source: "Foundation ProcessInfo and Metal",
    capability: .publicAPI,
    domain: .memory,
    accessLevel: .publicOrdinary,
    compatibilityConfidence: .documentedPlatformContract
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let capacity = ProcessInfo.processInfo.physicalMemory
    guard capacity > 0 else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Physical memory capacity was unavailable",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability
      )
    }
    var channels = [
      HardwareInventoryChannel.bytes("physical_capacity", "Physical memory capacity", capacity)
    ]
    if let device = MTLCreateSystemDefaultDevice() {
      channels.append(
        HardwareInventoryChannel.boolean(
          "unified_memory_architecture", "Unified memory architecture", device.hasUnifiedMemory
        ))
    }
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: SensorFormatting.bytes(capacity),
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels
    )
  }
}

public struct GPUHardwareProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "hardware.gpu",
    name: "Metal GPU",
    category: .system,
    source: "Metal device capabilities",
    capability: .publicAPI,
    domain: .gpu,
    accessLevel: .publicOrdinary,
    compatibilityConfidence: .documentedPlatformContract
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let devices = MTLCopyAllDevices()
    guard let primary = MTLCreateSystemDefaultDevice(),
      let name = HardwareInventorySanitizer.displayName(primary.name),
      !devices.isEmpty
    else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Metal GPU capabilities were unavailable",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability
      )
    }

    let maximumThreads = primary.maxThreadsPerThreadgroup
    let workingSet = UInt64(primary.recommendedMaxWorkingSetSize)
    let maximumBuffer = UInt64(primary.maxBufferLength)
    let channels: [SensorChannel] = [
      HardwareInventoryChannel.integer("gpu_count", "Metal GPU count", devices.count),
      SensorChannel(id: "primary_gpu_name", label: "Primary GPU", formattedValue: name),
      HardwareInventoryChannel.boolean(
        "unified_memory", "Uses unified memory", primary.hasUnifiedMemory
      ),
      HardwareInventoryChannel.boolean("low_power", "Low-power GPU", primary.isLowPower),
      HardwareInventoryChannel.boolean("removable", "Removable GPU", primary.isRemovable),
      HardwareInventoryChannel.boolean("headless", "Headless GPU", primary.isHeadless),
      HardwareInventoryChannel.bytes(
        "recommended_working_set", "Recommended GPU working set", workingSet
      ),
      HardwareInventoryChannel.bytes(
        "maximum_buffer_length", "Maximum buffer length", maximumBuffer),
      HardwareInventoryChannel.integer(
        "maximum_threadgroup_width", "Maximum threadgroup width", maximumThreads.width
      ),
      HardwareInventoryChannel.integer(
        "maximum_threadgroup_height", "Maximum threadgroup height", maximumThreads.height
      ),
      HardwareInventoryChannel.integer(
        "maximum_threadgroup_depth", "Maximum threadgroup depth", maximumThreads.depth
      ),
      HardwareInventoryChannel.boolean(
        "ray_tracing_supported", "Ray tracing supported", primary.supportsRaytracing
      ),
    ]
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: name,
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: ["Metal registry identifiers are intentionally not collected or exported."]
    )
  }
}

public struct SecurityHardwareProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "hardware.security",
    name: "Security Hardware",
    category: .system,
    source: "LocalAuthentication capability check",
    capability: .publicAPI,
    domain: .securityHardware,
    accessLevel: .publicOrdinary,
    compatibilityConfidence: .documentedPlatformContract
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let context = LAContext()
    var evaluationError: NSError?
    _ = context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      error: &evaluationError
    )
    let hasTouchID = context.biometryType == .touchID
    let readiness = SensorReadiness(
      hardwarePresence: hasTouchID ? .present : .absent,
      decoder: .notApplicable,
      readPath: .ready,
      stream: .notApplicable,
      feature: hasTouchID ? .ready : .unsupported
    )
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: hasTouchID ? "Touch ID available" : "Touch ID not detected",
      status: hasTouchID ? .available : .unavailable,
      source: metadata.source,
      capability: metadata.capability,
      readiness: readiness,
      channels: [
        SensorChannel(
          id: "touch_id_capability",
          label: "Touch ID capability",
          value: hasTouchID ? 1 : 0,
          formattedValue: hasTouchID ? "Detected" : "Not detected",
          note: "Capability only; no authentication prompt or enrollment state is requested."
        )
      ],
      notes: ["Secure Enclave presence is not inferred from Touch ID capability."]
    )
  }
}
