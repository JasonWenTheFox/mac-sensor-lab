import Foundation

public enum SensorCategory: String, Codable, CaseIterable, Sendable {
  case system
  case power
  case thermal
  case display
  case storage
  case motion
  case environment
  case input
  case diagnostics

  public var displayName: String {
    switch self {
    case .system: "System"
    case .power: "Power & Battery"
    case .thermal: "Thermals"
    case .display: "Display"
    case .storage: "Storage"
    case .motion: "Motion"
    case .environment: "Environment"
    case .input: "Input"
    case .diagnostics: "Diagnostics"
    }
  }
}

public enum SensorStatus: String, Codable, Sendable {
  case loading
  case available
  case degraded
  case permissionRequired
  case unavailable
  case error

  public var displayName: String {
    switch self {
    case .loading: "Loading"
    case .available: "Available"
    case .degraded: "Limited"
    case .permissionRequired: "Permission required"
    case .unavailable: "Unavailable"
    case .error: "Error"
    }
  }
}

public struct SensorStatusCounts: Equatable, Sendable {
  public let loading: Int
  public let available: Int
  public let degraded: Int
  public let permissionRequired: Int
  public let unavailable: Int
  public let error: Int

  public init(snapshots: [SensorSnapshot]) {
    var loading = 0
    var available = 0
    var degraded = 0
    var permissionRequired = 0
    var unavailable = 0
    var error = 0

    for snapshot in snapshots {
      switch snapshot.status {
      case .loading: loading += 1
      case .available: available += 1
      case .degraded: degraded += 1
      case .permissionRequired: permissionRequired += 1
      case .unavailable: unavailable += 1
      case .error: error += 1
      }
    }

    self.loading = loading
    self.available = available
    self.degraded = degraded
    self.permissionRequired = permissionRequired
    self.unavailable = unavailable
    self.error = error
  }
}

public enum SensorValueKind: String, Codable, Sendable {
  case raw
  case derived
  case estimated
  case calibrated

  public var displayName: String { rawValue.capitalized }
}

public enum SensorCapability: String, Codable, Sendable {
  case publicAPI
  case publicAPIWithPermission
  case undocumented
  case privileged
  case unsupported

  public var displayName: String {
    switch self {
    case .publicAPI: "Public API"
    case .publicAPIWithPermission: "Public API + permission"
    case .undocumented: "Undocumented"
    case .privileged: "Privileged"
    case .unsupported: "Unsupported"
    }
  }
}

/// The physical or logical hardware area represented by a provider.
///
/// This is intentionally independent from the dashboard category: a provider can remain in the
/// familiar "System" section while still declaring that its readings describe the GPU or memory.
public enum HardwareDomain: String, Codable, CaseIterable, Sendable {
  case system
  case soc
  case cpu
  case gpu
  case neuralEngine
  case memory
  case power
  case battery
  case thermal
  case fan
  case storage
  case display
  case motion
  case ambientLight
  case lid
  case trackpad
  case keyboardInput
  case audio
  case camera
  case wifi
  case bluetooth
  case usb
  case thunderbolt
  case securityHardware
  case network
  case externalSensors
  case diagnostics

  public var displayName: String {
    switch self {
    case .system: "System Hardware"
    case .soc: "SoC"
    case .cpu: "CPU"
    case .gpu: "GPU"
    case .neuralEngine: "Neural Engine"
    case .memory: "Memory"
    case .power: "Power"
    case .battery: "Battery"
    case .thermal: "Thermal"
    case .fan: "Fans"
    case .storage: "Storage"
    case .display: "Display"
    case .motion: "Motion"
    case .ambientLight: "Ambient Light"
    case .lid: "Lid"
    case .trackpad: "Trackpad"
    case .keyboardInput: "Keyboard"
    case .audio: "Audio"
    case .camera: "Camera"
    case .wifi: "Wi-Fi"
    case .bluetooth: "Bluetooth"
    case .usb: "USB"
    case .thunderbolt: "Thunderbolt"
    case .securityHardware: "Security Hardware"
    case .network: "Network"
    case .externalSensors: "External Sensors"
    case .diagnostics: "Diagnostics"
    }
  }
}

/// How the app reaches a provider, without conflating access with value quality or availability.
public enum SensorAccessLevel: String, Codable, CaseIterable, Sendable {
  case publicOrdinary
  case publicTCC
  case publicEntitlement
  case undocumentedOrdinary
  case privilegedHelper
  case privateExperimental
  case platformBlocked
  case hardwareAbsent

  public var displayName: String {
    switch self {
    case .publicOrdinary: "Public API"
    case .publicTCC: "Public API + privacy permission"
    case .publicEntitlement: "Public API + entitlement"
    case .undocumentedOrdinary: "Undocumented user access"
    case .privilegedHelper: "Privileged helper"
    case .privateExperimental: "Private experimental access"
    case .platformBlocked: "Blocked by platform"
    case .hardwareAbsent: "Hardware absent"
    }
  }

  public init(legacyCapability: SensorCapability) {
    self =
      switch legacyCapability {
      case .publicAPI: .publicOrdinary
      case .publicAPIWithPermission: .publicTCC
      case .undocumented: .undocumentedOrdinary
      case .privileged: .privilegedHelper
      case .unsupported: .platformBlocked
      }
  }

  public var legacyCapability: SensorCapability {
    switch self {
    case .publicOrdinary: .publicAPI
    case .publicTCC, .publicEntitlement: .publicAPIWithPermission
    case .undocumentedOrdinary, .privateExperimental: .undocumented
    case .privilegedHelper: .privileged
    case .platformBlocked, .hardwareAbsent: .unsupported
    }
  }
}

/// The evidence level behind a compatibility claim. This must describe evidence, not optimism.
public enum SensorCompatibilityConfidence: String, Codable, CaseIterable, Sendable {
  case unknown
  case fixtureValidated
  case singleModelObserved
  case multiModelObserved
  case documentedPlatformContract

  public var displayName: String {
    switch self {
    case .unknown: "Compatibility unknown"
    case .fixtureValidated: "Fixture validated"
    case .singleModelObserved: "Observed on one model"
    case .multiModelObserved: "Observed on multiple models"
    case .documentedPlatformContract: "Documented platform contract"
    }
  }
}

public enum SensorHardwarePresence: String, Codable, Sendable {
  case unknown
  case present
  case absent
  case mixed
  case notApplicable

  public var displayName: String {
    switch self {
    case .unknown: "Unknown"
    case .present: "Present"
    case .absent: "Absent"
    case .mixed: "Mixed"
    case .notApplicable: "Not applicable"
    }
  }
}

public enum SensorDecoderReadiness: String, Codable, Sendable {
  case unknown
  case ready
  case notApplicable
  case unsupported

  public var displayName: String {
    switch self {
    case .unknown: "Unknown"
    case .ready: "Decoder ready"
    case .notApplicable: "Not applicable"
    case .unsupported: "Decoder unsupported"
    }
  }
}

public enum SensorReadPathReadiness: String, Codable, Sendable {
  case unknown
  case ready
  case limited
  case permissionRequired
  case unavailable
  case failed

  public var displayName: String {
    switch self {
    case .unknown: "Unknown"
    case .ready: "Read path ready"
    case .limited: "Read path limited"
    case .permissionRequired: "Permission required"
    case .unavailable: "Read path unavailable"
    case .failed: "Read path failed"
    }
  }
}

public enum SensorStreamReadiness: String, Codable, Sendable {
  case unknown
  case active
  case inactive
  case notApplicable

  public var displayName: String {
    switch self {
    case .unknown: "Unknown"
    case .active: "Stream active"
    case .inactive: "Stream inactive"
    case .notApplicable: "Not applicable"
    }
  }
}

public enum SensorFeatureReadiness: String, Codable, Sendable {
  case unknown
  case ready
  case partial
  case blocked
  case unsupported
  case notApplicable

  public var displayName: String {
    switch self {
    case .unknown: "Unknown"
    case .ready: "Feature ready"
    case .partial: "Feature partial"
    case .blocked: "Feature blocked"
    case .unsupported: "Feature unsupported"
    case .notApplicable: "Not applicable"
    }
  }
}

/// Five independent checkpoints between hardware presence and a useful user-facing feature.
public struct SensorReadiness: Codable, Equatable, Sendable {
  public let hardwarePresence: SensorHardwarePresence
  public let decoder: SensorDecoderReadiness
  public let readPath: SensorReadPathReadiness
  public let stream: SensorStreamReadiness
  public let feature: SensorFeatureReadiness

  public init(
    hardwarePresence: SensorHardwarePresence,
    decoder: SensorDecoderReadiness,
    readPath: SensorReadPathReadiness,
    stream: SensorStreamReadiness,
    feature: SensorFeatureReadiness
  ) {
    self.hardwarePresence = hardwarePresence
    self.decoder = decoder
    self.readPath = readPath
    self.stream = stream
    self.feature = feature
  }

  static func inferred(
    providerID: String,
    status: SensorStatus,
    accessLevel: SensorAccessLevel,
    hasChannels: Bool
  ) -> SensorReadiness {
    let usesDecoder = accessLevel == .undocumentedOrdinary || accessLevel == .privateExperimental
    let isStream = SensorSemanticProfile.streamingProviderIDs.contains(providerID)

    let hardwarePresence: SensorHardwarePresence
    if accessLevel == .hardwareAbsent {
      hardwarePresence = .absent
    } else if status == .available || (status == .degraded && hasChannels) {
      hardwarePresence = .present
    } else {
      hardwarePresence = .unknown
    }

    let decoder: SensorDecoderReadiness
    if !usesDecoder {
      decoder = .notApplicable
    } else if hasChannels && (status == .available || status == .degraded) {
      decoder = .ready
    } else {
      decoder = .unknown
    }

    let readPath: SensorReadPathReadiness =
      switch status {
      case .loading: .unknown
      case .available: .ready
      case .degraded: .limited
      case .permissionRequired: .permissionRequired
      case .unavailable: .unavailable
      case .error: .failed
      }
    let stream: SensorStreamReadiness
    if !isStream {
      stream = .notApplicable
    } else {
      stream = status == .available ? .active : .inactive
    }
    let feature: SensorFeatureReadiness =
      switch status {
      case .loading: .unknown
      case .available: .ready
      case .degraded: .partial
      case .permissionRequired: .blocked
      case .unavailable, .error: .unknown
      }

    return SensorReadiness(
      hardwarePresence: hardwarePresence,
      decoder: decoder,
      readPath: readPath,
      stream: stream,
      feature: feature
    )
  }
}

private struct SensorSemanticProfile {
  let domain: HardwareDomain
  let accessLevel: SensorAccessLevel
  let compatibilityConfidence: SensorCompatibilityConfidence

  static let streamingProviderIDs: Set<String> = [
    "system.performance",
    "system.gpu_performance",
    "system.network_throughput",
    "storage.disk_io",
    "motion.spu_live",
  ]

  static func resolve(
    providerID: String,
    category: SensorCategory,
    legacyCapability: SensorCapability
  ) -> SensorSemanticProfile {
    let domain: HardwareDomain =
      switch providerID {
      case "system.gpu_performance", "hardware.gpu": .gpu
      case "system.network_throughput": .network
      case "power.source": .power
      case "power.battery": .battery
      case "thermal.pressure", "thermal.smc": .thermal
      case "display.active": .display
      case "storage.system_volume", "storage.disk_io": .storage
      case "motion.spu_discovery", "motion.spu_live": .motion
      case "motion.lid_angle": .lid
      case "hardware.soc": .soc
      case "hardware.cpu": .cpu
      case "hardware.memory": .memory
      case "hardware.security": .securityHardware
      case "diagnostics.hardware_capabilities": .diagnostics
      default:
        switch category {
        case .system: .system
        case .power: .power
        case .thermal: .thermal
        case .display: .display
        case .storage: .storage
        case .motion: .motion
        case .environment: .externalSensors
        case .input: .trackpad
        case .diagnostics: .diagnostics
        }
      }

    let accessLevel: SensorAccessLevel =
      switch providerID {
      case "motion.spu_discovery", "motion.spu_live", "motion.lid_angle", "thermal.smc":
        .privateExperimental
      case "system.gpu_performance", "system.network_throughput", "power.battery",
        "storage.disk_io", "diagnostics.hardware_capabilities", "hardware.platform",
        "hardware.soc", "hardware.cpu":
        .undocumentedOrdinary
      default:
        SensorAccessLevel(legacyCapability: legacyCapability)
      }

    let compatibilityConfidence: SensorCompatibilityConfidence =
      switch accessLevel {
      case .publicOrdinary, .publicTCC, .publicEntitlement:
        .documentedPlatformContract
      case .undocumentedOrdinary, .privateExperimental:
        .singleModelObserved
      case .privilegedHelper, .platformBlocked, .hardwareAbsent:
        .unknown
      }
    return SensorSemanticProfile(
      domain: domain,
      accessLevel: accessLevel,
      compatibilityConfidence: compatibilityConfidence
    )
  }
}

public struct SensorChannel: Identifiable, Codable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let value: Double?
  public let formattedValue: String
  public let unit: String?
  public let kind: SensorValueKind
  public let note: String?

  public init(
    id: String,
    label: String,
    value: Double? = nil,
    formattedValue: String,
    unit: String? = nil,
    kind: SensorValueKind = .raw,
    note: String? = nil
  ) {
    self.id = id
    self.label = label
    self.value = value
    self.formattedValue = formattedValue
    self.unit = unit
    self.kind = kind
    self.note = note
  }
}

public struct SensorSnapshot: Identifiable, Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let category: SensorCategory
  public let summary: String
  public let status: SensorStatus
  public let source: String
  public let capability: SensorCapability
  public let domain: HardwareDomain
  public let accessLevel: SensorAccessLevel
  public let compatibilityConfidence: SensorCompatibilityConfidence
  public let readiness: SensorReadiness
  public let channels: [SensorChannel]
  public let notes: [String]
  public let timestamp: Date

  public init(
    id: String,
    name: String,
    category: SensorCategory,
    summary: String,
    status: SensorStatus,
    source: String,
    capability: SensorCapability,
    domain: HardwareDomain? = nil,
    accessLevel: SensorAccessLevel? = nil,
    compatibilityConfidence: SensorCompatibilityConfidence? = nil,
    readiness: SensorReadiness? = nil,
    channels: [SensorChannel] = [],
    notes: [String] = [],
    timestamp: Date = .now
  ) {
    self.id = id
    self.name = name
    self.category = category
    self.summary = summary
    self.status = status
    self.source = source
    self.capability = capability
    let profile = SensorSemanticProfile.resolve(
      providerID: id,
      category: category,
      legacyCapability: capability
    )
    let resolvedAccessLevel = accessLevel ?? profile.accessLevel
    self.domain = domain ?? profile.domain
    self.accessLevel = resolvedAccessLevel
    self.compatibilityConfidence = compatibilityConfidence ?? profile.compatibilityConfidence
    self.readiness =
      readiness
      ?? SensorReadiness.inferred(
        providerID: id,
        status: status,
        accessLevel: resolvedAccessLevel,
        hasChannels: !channels.isEmpty
      )
    self.channels = channels
    self.notes = notes
    self.timestamp = timestamp
  }

  public static func loading(metadata: SensorProviderMetadata) -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "Reading in the background…",
      status: .loading,
      source: metadata.source,
      capability: metadata.capability,
      domain: metadata.domain,
      accessLevel: metadata.accessLevel,
      compatibilityConfidence: metadata.compatibilityConfidence
    )
  }
}

public struct SensorProviderMetadata: Identifiable, Sendable {
  public let id: String
  public let name: String
  public let category: SensorCategory
  public let source: String
  public let capability: SensorCapability
  public let domain: HardwareDomain
  public let accessLevel: SensorAccessLevel
  public let compatibilityConfidence: SensorCompatibilityConfidence

  public init(
    id: String,
    name: String,
    category: SensorCategory,
    source: String,
    capability: SensorCapability,
    domain: HardwareDomain? = nil,
    accessLevel: SensorAccessLevel? = nil,
    compatibilityConfidence: SensorCompatibilityConfidence? = nil
  ) {
    self.id = id
    self.name = name
    self.category = category
    self.source = source
    self.capability = capability
    let profile = SensorSemanticProfile.resolve(
      providerID: id,
      category: category,
      legacyCapability: capability
    )
    self.domain = domain ?? profile.domain
    self.accessLevel = accessLevel ?? profile.accessLevel
    self.compatibilityConfidence = compatibilityConfidence ?? profile.compatibilityConfidence
  }
}

public protocol SensorProvider: Sendable {
  var metadata: SensorProviderMetadata { get }
  func read() async -> SensorSnapshot
}
