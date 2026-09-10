import Foundation

public enum USBInventoryRawNumber: Equatable, Sendable {
  case missing
  case integer(Int64)
  case malformed
}

public struct USBInventoryRawDevice: Equatable, Sendable {
  public let sourceIndex: Int
  public let parentSourceIndex: Int?
  public let vendorID: USBInventoryRawNumber
  public let productID: USBInventoryRawNumber
  public let deviceReleaseNumber: USBInventoryRawNumber
  public let deviceClass: USBInventoryRawNumber
  public let deviceSubClass: USBInventoryRawNumber
  public let deviceProtocol: USBInventoryRawNumber
  public let currentConfiguration: USBInventoryRawNumber
  public let connectionSpeed: USBInventoryRawNumber

  public init(
    sourceIndex: Int,
    parentSourceIndex: Int? = nil,
    vendorID: USBInventoryRawNumber = .missing,
    productID: USBInventoryRawNumber = .missing,
    deviceReleaseNumber: USBInventoryRawNumber = .missing,
    deviceClass: USBInventoryRawNumber = .missing,
    deviceSubClass: USBInventoryRawNumber = .missing,
    deviceProtocol: USBInventoryRawNumber = .missing,
    currentConfiguration: USBInventoryRawNumber = .missing,
    connectionSpeed: USBInventoryRawNumber = .missing
  ) {
    self.sourceIndex = sourceIndex
    self.parentSourceIndex = parentSourceIndex
    self.vendorID = vendorID
    self.productID = productID
    self.deviceReleaseNumber = deviceReleaseNumber
    self.deviceClass = deviceClass
    self.deviceSubClass = deviceSubClass
    self.deviceProtocol = deviceProtocol
    self.currentConfiguration = currentConfiguration
    self.connectionSpeed = connectionSpeed
  }
}

public struct USBInventoryRawInterface: Equatable, Sendable {
  public let sourceIndex: Int
  public let parentDeviceSourceIndex: Int?
  public let interfaceNumber: USBInventoryRawNumber
  public let interfaceClass: USBInventoryRawNumber
  public let interfaceSubClass: USBInventoryRawNumber
  public let interfaceProtocol: USBInventoryRawNumber
  public let alternateSetting: USBInventoryRawNumber

  public init(
    sourceIndex: Int,
    parentDeviceSourceIndex: Int?,
    interfaceNumber: USBInventoryRawNumber = .missing,
    interfaceClass: USBInventoryRawNumber = .missing,
    interfaceSubClass: USBInventoryRawNumber = .missing,
    interfaceProtocol: USBInventoryRawNumber = .missing,
    alternateSetting: USBInventoryRawNumber = .missing
  ) {
    self.sourceIndex = sourceIndex
    self.parentDeviceSourceIndex = parentDeviceSourceIndex
    self.interfaceNumber = interfaceNumber
    self.interfaceClass = interfaceClass
    self.interfaceSubClass = interfaceSubClass
    self.interfaceProtocol = interfaceProtocol
    self.alternateSetting = alternateSetting
  }
}

public enum USBInventoryConnectionSpeed: UInt8, Equatable, Sendable {
  case notConnected = 0
  case full = 1
  case low = 2
  case high = 3
  case superSpeed = 4
  case superSpeedPlus = 5
  case superSpeedPlusBy2 = 6
  case other = 7

  public var displayName: String {
    switch self {
    case .notConnected: "Not connected"
    case .full: "Full Speed — 12 Mb/s"
    case .low: "Low Speed — 1.5 Mb/s"
    case .high: "High Speed — 480 Mb/s"
    case .superSpeed: "SuperSpeed — 5 Gb/s"
    case .superSpeedPlus: "SuperSpeed+ — 10 Gb/s"
    case .superSpeedPlusBy2: "SuperSpeed+ ×2 — 20 Gb/s"
    case .other: "Other reported speed"
    }
  }
}

public enum USBInventoryClassName {
  public static func displayName(for code: UInt8, deviceContext: Bool) -> String? {
    switch code {
    case 0 where deviceContext: "Defined by interfaces"
    case 1: "Audio"
    case 2: "Communications"
    case 3: "Human interface device"
    case 5: "Physical"
    case 6: "Image"
    case 7: "Printer"
    case 8: "Mass storage"
    case 9: "Hub"
    case 10: "CDC data"
    case 11: "Smart card"
    case 13: "Content security"
    case 14: "Video"
    case 15: "Personal healthcare"
    case 17: "Billboard"
    case 220: "Diagnostic"
    case 224: "Wireless controller"
    case 239: "Miscellaneous"
    case 254: "Application specific"
    case 255: "Vendor specific"
    default: nil
    }
  }
}

public struct USBInventoryInterface: Identifiable, Equatable, Sendable {
  public let id: Int
  public let ordinal: Int
  public let interfaceNumber: UInt8?
  public let interfaceClass: UInt8?
  public let interfaceSubClass: UInt8?
  public let interfaceProtocol: UInt8?
  public let alternateSetting: UInt8?
}

public struct USBInventoryDevice: Identifiable, Equatable, Sendable {
  public let id: Int
  public let ordinal: Int
  public let parentOrdinal: Int?
  public let depth: Int
  public let vendorID: UInt16?
  public let productID: UInt16?
  public let deviceReleaseNumber: UInt16?
  public let deviceClass: UInt8?
  public let deviceSubClass: UInt8?
  public let deviceProtocol: UInt8?
  public let currentConfiguration: UInt8?
  public let connectionSpeed: USBInventoryConnectionSpeed?
  public let interfaces: [USBInventoryInterface]
}

public struct USBInventorySnapshot: Equatable, Sendable {
  public let completedAt: Date
  public let devices: [USBInventoryDevice]
  public let reportedDeviceCount: Int
  public let reportedInterfaceCount: Int
  public let discardedInterfaceCount: Int
  public let malformedFieldCount: Int

  public var acceptedInterfaceCount: Int {
    devices.reduce(0) { $0 + $1.interfaces.count }
  }

  public var isLimited: Bool {
    discardedInterfaceCount > 0 || malformedFieldCount > 0
  }
}

public enum USBInventoryFailure: String, Equatable, Sendable {
  case operationNotPermitted
  case unsupported
  case enumerationUnavailable
  case safetyLimitReached
  case invalidTopology
  case failed
}

public enum USBInventoryOutcome: Equatable, Sendable {
  case success(USBInventorySnapshot)
  case failure(USBInventoryFailure)
}

public enum USBInventoryReducer {
  public static let maximumDeviceCount = 128
  public static let maximumInterfaceCount = 512
  public static let maximumHierarchyDepth = 32

  public static func reduce(
    devices rawDevices: [USBInventoryRawDevice],
    interfaces rawInterfaces: [USBInventoryRawInterface],
    completedAt: Date = Date()
  ) -> USBInventoryOutcome {
    guard rawDevices.count <= maximumDeviceCount,
      rawInterfaces.count <= maximumInterfaceCount
    else {
      return .failure(.safetyLimitReached)
    }

    let deviceIndices = rawDevices.map(\.sourceIndex)
    let interfaceIndices = rawInterfaces.map(\.sourceIndex)
    guard deviceIndices.allSatisfy({ $0 >= 0 }),
      interfaceIndices.allSatisfy({ $0 >= 0 }),
      Set(deviceIndices).count == deviceIndices.count,
      Set(interfaceIndices).count == interfaceIndices.count
    else {
      return .failure(.invalidTopology)
    }

    let rawByIndex = Dictionary(uniqueKeysWithValues: rawDevices.map { ($0.sourceIndex, $0) })
    guard
      rawDevices.allSatisfy({ device in
        guard let parent = device.parentSourceIndex else { return true }
        return parent != device.sourceIndex && rawByIndex[parent] != nil
      })
    else {
      return .failure(.invalidTopology)
    }

    var depthCache: [Int: Int] = [:]
    var visiting = Set<Int>()
    func depth(for index: Int) -> Int? {
      if let cached = depthCache[index] { return cached }
      guard visiting.insert(index).inserted, let device = rawByIndex[index] else { return nil }
      defer { visiting.remove(index) }
      let value: Int
      if let parent = device.parentSourceIndex {
        guard let parentDepth = depth(for: parent), parentDepth < maximumHierarchyDepth - 1 else {
          return nil
        }
        value = parentDepth + 1
      } else {
        value = 0
      }
      depthCache[index] = value
      return value
    }

    guard rawDevices.allSatisfy({ depth(for: $0.sourceIndex) != nil }) else {
      return .failure(.invalidTopology)
    }

    let children = Dictionary(grouping: rawDevices, by: \.parentSourceIndex)
    var preorder: [USBInventoryRawDevice] = []
    func appendSubtree(_ device: USBInventoryRawDevice) {
      preorder.append(device)
      for child in children[device.sourceIndex, default: []].sorted(by: sourceOrder) {
        appendSubtree(child)
      }
    }
    for root in children[nil, default: []].sorted(by: sourceOrder) {
      appendSubtree(root)
    }
    guard preorder.count == rawDevices.count else {
      return .failure(.invalidTopology)
    }

    let ordinalByIndex = Dictionary(
      uniqueKeysWithValues: preorder.enumerated().map { ($0.element.sourceIndex, $0.offset + 1) }
    )
    let validParentIndices = Set(deviceIndices)
    let attachedInterfaces = rawInterfaces.filter {
      guard let parent = $0.parentDeviceSourceIndex else { return false }
      return validParentIndices.contains(parent)
    }
    let interfacesByParent = Dictionary(grouping: attachedInterfaces) {
      $0.parentDeviceSourceIndex!
    }
    var malformedFieldCount = 0

    let devices = preorder.map { raw -> USBInventoryDevice in
      let ordinal = ordinalByIndex[raw.sourceIndex]!
      let rawChildren = interfacesByParent[raw.sourceIndex, default: []].sorted(by: interfaceOrder)
      let interfaces = rawChildren.enumerated().map { offset, item in
        USBInventoryInterface(
          id: item.sourceIndex,
          ordinal: offset + 1,
          interfaceNumber: uint8(item.interfaceNumber, malformed: &malformedFieldCount),
          interfaceClass: uint8(item.interfaceClass, malformed: &malformedFieldCount),
          interfaceSubClass: uint8(item.interfaceSubClass, malformed: &malformedFieldCount),
          interfaceProtocol: uint8(item.interfaceProtocol, malformed: &malformedFieldCount),
          alternateSetting: uint8(item.alternateSetting, malformed: &malformedFieldCount)
        )
      }
      return USBInventoryDevice(
        id: raw.sourceIndex,
        ordinal: ordinal,
        parentOrdinal: raw.parentSourceIndex.flatMap { ordinalByIndex[$0] },
        depth: depthCache[raw.sourceIndex]!,
        vendorID: uint16(raw.vendorID, malformed: &malformedFieldCount),
        productID: uint16(raw.productID, malformed: &malformedFieldCount),
        deviceReleaseNumber: uint16(
          raw.deviceReleaseNumber,
          malformed: &malformedFieldCount
        ),
        deviceClass: uint8(raw.deviceClass, malformed: &malformedFieldCount),
        deviceSubClass: uint8(raw.deviceSubClass, malformed: &malformedFieldCount),
        deviceProtocol: uint8(raw.deviceProtocol, malformed: &malformedFieldCount),
        currentConfiguration: uint8(
          raw.currentConfiguration,
          malformed: &malformedFieldCount
        ),
        connectionSpeed: connectionSpeed(
          raw.connectionSpeed,
          malformed: &malformedFieldCount
        ),
        interfaces: interfaces
      )
    }

    return .success(
      USBInventorySnapshot(
        completedAt: completedAt,
        devices: devices,
        reportedDeviceCount: rawDevices.count,
        reportedInterfaceCount: rawInterfaces.count,
        discardedInterfaceCount: rawInterfaces.count - attachedInterfaces.count,
        malformedFieldCount: malformedFieldCount
      )
    )
  }

  private static func sourceOrder(_ lhs: USBInventoryRawDevice, _ rhs: USBInventoryRawDevice)
    -> Bool
  {
    lhs.sourceIndex < rhs.sourceIndex
  }

  private static func interfaceOrder(
    _ lhs: USBInventoryRawInterface,
    _ rhs: USBInventoryRawInterface
  ) -> Bool {
    lhs.sourceIndex < rhs.sourceIndex
  }

  private static func uint8(
    _ raw: USBInventoryRawNumber,
    malformed count: inout Int
  ) -> UInt8? {
    guard let value = bounded(raw, maximum: UInt64(UInt8.max), malformed: &count) else {
      return nil
    }
    return UInt8(value)
  }

  private static func uint16(
    _ raw: USBInventoryRawNumber,
    malformed count: inout Int
  ) -> UInt16? {
    guard let value = bounded(raw, maximum: UInt64(UInt16.max), malformed: &count) else {
      return nil
    }
    return UInt16(value)
  }

  private static func connectionSpeed(
    _ raw: USBInventoryRawNumber,
    malformed count: inout Int
  ) -> USBInventoryConnectionSpeed? {
    switch raw {
    case .missing:
      return nil
    case .malformed:
      count += 1
      return nil
    case .integer(let value):
      guard value >= 0, value <= Int64(UInt8.max),
        let speed = USBInventoryConnectionSpeed(rawValue: UInt8(value))
      else {
        count += 1
        return nil
      }
      return speed
    }
  }

  private static func bounded(
    _ raw: USBInventoryRawNumber,
    maximum: UInt64,
    malformed count: inout Int
  ) -> UInt64? {
    switch raw {
    case .missing:
      return nil
    case .malformed:
      count += 1
      return nil
    case .integer(let value):
      guard value >= 0, UInt64(value) <= maximum else {
        count += 1
        return nil
      }
      return UInt64(value)
    }
  }
}
