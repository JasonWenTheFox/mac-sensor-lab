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
      capability: metadata.capability
    )
  }
}

public struct SensorProviderMetadata: Identifiable, Sendable {
  public let id: String
  public let name: String
  public let category: SensorCategory
  public let source: String
  public let capability: SensorCapability

  public init(
    id: String,
    name: String,
    category: SensorCategory,
    source: String,
    capability: SensorCapability
  ) {
    self.id = id
    self.name = name
    self.category = category
    self.source = source
    self.capability = capability
  }
}

public protocol SensorProvider: Sendable {
  var metadata: SensorProviderMetadata { get }
  func read() async -> SensorSnapshot
}
