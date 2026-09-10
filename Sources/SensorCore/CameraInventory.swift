import CoreAudio
import Foundation

public enum CameraInventoryRawDeviceType: Equatable, Sendable {
  case builtInWideAngle
  case external
  case continuityCamera
  case deskViewCamera
  case unsupported
}

public struct CameraInventoryRawFrameRateRange: Equatable, Sendable {
  public let minimum: Double
  public let maximum: Double

  public init(minimum: Double, maximum: Double) {
    self.minimum = minimum
    self.maximum = maximum
  }
}

public struct CameraInventoryRawFormat: Equatable, Sendable {
  public let sourceIndex: Int
  public let width: Int64
  public let height: Int64
  public let frameRateRanges: [CameraInventoryRawFrameRateRange]
  public let autofocusSystemRawValue: Int
  public let colorSpaceRawValues: [Int]

  public init(
    sourceIndex: Int,
    width: Int64,
    height: Int64,
    frameRateRanges: [CameraInventoryRawFrameRateRange],
    autofocusSystemRawValue: Int,
    colorSpaceRawValues: [Int]
  ) {
    self.sourceIndex = sourceIndex
    self.width = width
    self.height = height
    self.frameRateRanges = frameRateRanges
    self.autofocusSystemRawValue = autofocusSystemRawValue
    self.colorSpaceRawValues = colorSpaceRawValues
  }
}

public struct CameraInventoryRawDevice: Equatable, Sendable {
  public let sourceIndex: Int
  public let deviceType: CameraInventoryRawDeviceType
  public let positionRawValue: Int
  public let transportRawValue: UInt32
  public let formats: [CameraInventoryRawFormat]

  public init(
    sourceIndex: Int,
    deviceType: CameraInventoryRawDeviceType,
    positionRawValue: Int = 0,
    transportRawValue: UInt32 = 0,
    formats: [CameraInventoryRawFormat] = []
  ) {
    self.sourceIndex = sourceIndex
    self.deviceType = deviceType
    self.positionRawValue = positionRawValue
    self.transportRawValue = transportRawValue
    self.formats = formats
  }
}

public enum CameraInventoryDeviceType: Equatable, Sendable {
  case builtInWideAngle
  case external

  public var displayName: String {
    switch self {
    case .builtInWideAngle: "Built-in wide-angle camera"
    case .external: "External camera"
    }
  }
}

public enum CameraInventoryPosition: Equatable, Sendable {
  case unspecified
  case front
  case back
  case unknown

  public var displayName: String {
    switch self {
    case .unspecified: "Unspecified"
    case .front: "Front"
    case .back: "Back"
    case .unknown: "Unknown"
    }
  }
}

public enum CameraInventoryTransport: Equatable, Sendable {
  case unknown
  case builtIn
  case aggregate
  case virtual
  case pci
  case usb
  case fireWire
  case bluetooth
  case bluetoothLE
  case hdmi
  case displayPort
  case airPlay
  case avb
  case thunderbolt

  public var displayName: String {
    switch self {
    case .unknown: "Unknown"
    case .builtIn: "Built-in"
    case .aggregate: "Aggregate"
    case .virtual: "Virtual"
    case .pci: "PCI"
    case .usb: "USB"
    case .fireWire: "FireWire"
    case .bluetooth: "Bluetooth"
    case .bluetoothLE: "Bluetooth LE"
    case .hdmi: "HDMI"
    case .displayPort: "DisplayPort"
    case .airPlay: "AirPlay"
    case .avb: "AVB"
    case .thunderbolt: "Thunderbolt"
    }
  }
}

public enum CameraInventoryAutofocusSystem: Equatable, Hashable, Sendable {
  case none
  case contrastDetection
  case phaseDetection
  case unknown

  public var displayName: String {
    switch self {
    case .none: "None"
    case .contrastDetection: "Contrast detection"
    case .phaseDetection: "Phase detection"
    case .unknown: "Unknown"
    }
  }
}

public enum CameraInventoryColorSpace: Equatable, Hashable, Sendable {
  case sRGB
  case p3D65
  case unknown

  public var displayName: String {
    switch self {
    case .sRGB: "sRGB"
    case .p3D65: "P3 D65"
    case .unknown: "Unknown"
    }
  }
}

public struct CameraInventoryCapability: Identifiable, Equatable, Sendable {
  public let id: Int
  public let width: Int
  public let height: Int
  public let minimumFrameRate: Double
  public let maximumFrameRate: Double
  public let autofocusSystem: CameraInventoryAutofocusSystem
  public let colorSpaces: [CameraInventoryColorSpace]
  public let variantCount: Int
}

public struct CameraInventoryDevice: Identifiable, Equatable, Sendable {
  public let id: Int
  public let ordinal: Int
  public let deviceType: CameraInventoryDeviceType
  public let position: CameraInventoryPosition
  public let transport: CameraInventoryTransport
  public let reportedFormatCount: Int
  public let capabilities: [CameraInventoryCapability]
}

public struct CameraInventorySnapshot: Equatable, Sendable {
  public let completedAt: Date
  public let devices: [CameraInventoryDevice]
  public let reportedDeviceCount: Int
  public let discardedDeviceCount: Int
  public let malformedFieldCount: Int

  public var capabilityRowCount: Int {
    devices.reduce(0) { $0 + $1.capabilities.count }
  }

  public var isLimited: Bool {
    discardedDeviceCount > 0 || malformedFieldCount > 0
  }
}

public enum CameraInventoryFailure: String, Equatable, Sendable {
  case continuityBoundaryMissing
  case discoveryUnavailable
  case safetyLimitReached
  case malformedData
  case failed
}

public enum CameraInventoryOutcome: Equatable, Sendable {
  case success(CameraInventorySnapshot)
  case failure(CameraInventoryFailure)
}

public enum CameraInventoryReducer {
  public static let maximumDeviceCount = 32
  public static let maximumFormatCountPerDevice = 256
  public static let maximumFrameRateRangeCountPerFormat = 32
  public static let maximumColorSpaceCountPerFormat = 8
  public static let maximumCapabilityRowCount = 8_192
  public static let maximumDimension = 32_768
  public static let maximumFrameRate = 1_000.0

  private static let legacyContinuityCaptureTransport: UInt32 = 0x6363_6170

  public static func reduce(
    devices rawDevices: [CameraInventoryRawDevice],
    completedAt: Date = Date()
  ) -> CameraInventoryOutcome {
    guard rawDevices.count <= maximumDeviceCount else {
      return .failure(.safetyLimitReached)
    }
    let sourceIndices = rawDevices.map(\.sourceIndex)
    guard sourceIndices.allSatisfy({ $0 >= 0 }),
      Set(sourceIndices).count == sourceIndices.count
    else {
      return .failure(.malformedData)
    }
    guard rawDevices.allSatisfy({ $0.formats.count <= maximumFormatCountPerDevice }) else {
      return .failure(.safetyLimitReached)
    }
    guard
      rawDevices.allSatisfy({ device in
        device.formats.allSatisfy {
          $0.frameRateRanges.count <= maximumFrameRateRangeCountPerFormat
            && $0.colorSpaceRawValues.count <= maximumColorSpaceCountPerFormat
        }
      })
    else {
      return .failure(.safetyLimitReached)
    }
    guard
      rawDevices.allSatisfy({ device in
        let indices = device.formats.map(\.sourceIndex)
        return indices.allSatisfy { $0 >= 0 } && Set(indices).count == indices.count
      })
    else {
      return .failure(.malformedData)
    }

    var discardedDeviceCount = 0
    var malformedFieldCount = 0
    var totalCapabilityRowCount = 0
    var devices: [CameraInventoryDevice] = []

    for rawDevice in rawDevices.sorted(by: { $0.sourceIndex < $1.sourceIndex }) {
      let deviceType: CameraInventoryDeviceType
      switch rawDevice.deviceType {
      case .builtInWideAngle:
        deviceType = .builtInWideAngle
      case .external:
        deviceType = .external
      case .continuityCamera, .deskViewCamera:
        discardedDeviceCount += 1
        continue
      case .unsupported:
        discardedDeviceCount += 1
        malformedFieldCount += 1
        continue
      }

      let transportClassification = transport(rawDevice.transportRawValue)
      if transportClassification.isContinuity {
        discardedDeviceCount += 1
        continue
      }
      if transportClassification.isUnrecognized {
        malformedFieldCount += 1
      }

      let position = position(rawDevice.positionRawValue, malformed: &malformedFieldCount)
      var accumulators: [CapabilityKey: Int] = [:]
      var rows: [CapabilityAccumulator] = []

      for rawFormat in rawDevice.formats.sorted(by: { $0.sourceIndex < $1.sourceIndex }) {
        let width = dimension(rawFormat.width, malformed: &malformedFieldCount)
        let height = dimension(rawFormat.height, malformed: &malformedFieldCount)
        guard let width, let height else {
          continue
        }
        guard !rawFormat.frameRateRanges.isEmpty else {
          malformedFieldCount += 1
          continue
        }

        let autofocus = autofocus(
          rawFormat.autofocusSystemRawValue,
          malformed: &malformedFieldCount
        )
        let colorSpaces = colorSpaces(
          rawFormat.colorSpaceRawValues,
          malformed: &malformedFieldCount
        )

        for rawRange in rawFormat.frameRateRanges {
          guard let range = frameRateRange(rawRange, malformed: &malformedFieldCount) else {
            continue
          }
          let key = CapabilityKey(
            width: width,
            height: height,
            minimumFrameRate: range.minimum,
            maximumFrameRate: range.maximum,
            autofocusSystem: autofocus,
            colorSpaces: colorSpaces
          )
          if let index = accumulators[key] {
            let (nextCount, overflow) = rows[index].variantCount.addingReportingOverflow(1)
            guard !overflow else { return .failure(.safetyLimitReached) }
            rows[index].variantCount = nextCount
          } else {
            guard totalCapabilityRowCount < maximumCapabilityRowCount else {
              return .failure(.safetyLimitReached)
            }
            accumulators[key] = rows.count
            rows.append(CapabilityAccumulator(key: key, variantCount: 1))
            totalCapabilityRowCount += 1
          }
        }
      }

      let ordinal = devices.count + 1
      devices.append(
        CameraInventoryDevice(
          id: ordinal,
          ordinal: ordinal,
          deviceType: deviceType,
          position: position,
          transport: transportClassification.value,
          reportedFormatCount: rawDevice.formats.count,
          capabilities: rows.enumerated().map { index, row in
            CameraInventoryCapability(
              id: index + 1,
              width: row.key.width,
              height: row.key.height,
              minimumFrameRate: row.key.minimumFrameRate,
              maximumFrameRate: row.key.maximumFrameRate,
              autofocusSystem: row.key.autofocusSystem,
              colorSpaces: row.key.colorSpaces,
              variantCount: row.variantCount
            )
          }
        )
      )
    }

    return .success(
      CameraInventorySnapshot(
        completedAt: completedAt,
        devices: devices,
        reportedDeviceCount: rawDevices.count,
        discardedDeviceCount: discardedDeviceCount,
        malformedFieldCount: malformedFieldCount
      )
    )
  }

  private struct CapabilityKey: Hashable {
    let width: Int
    let height: Int
    let minimumFrameRate: Double
    let maximumFrameRate: Double
    let autofocusSystem: CameraInventoryAutofocusSystem
    let colorSpaces: [CameraInventoryColorSpace]
  }

  private struct CapabilityAccumulator {
    let key: CapabilityKey
    var variantCount: Int
  }

  private struct TransportClassification {
    let value: CameraInventoryTransport
    let isContinuity: Bool
    let isUnrecognized: Bool
  }

  private static func position(
    _ rawValue: Int,
    malformed count: inout Int
  ) -> CameraInventoryPosition {
    switch rawValue {
    case 0: return .unspecified
    case 1: return .back
    case 2: return .front
    default:
      count += 1
      return .unknown
    }
  }

  private static func transport(_ rawValue: UInt32) -> TransportClassification {
    switch rawValue {
    case kAudioDeviceTransportTypeUnknown:
      TransportClassification(value: .unknown, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeBuiltIn:
      TransportClassification(value: .builtIn, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeAggregate:
      TransportClassification(value: .aggregate, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeVirtual:
      TransportClassification(value: .virtual, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypePCI:
      TransportClassification(value: .pci, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeUSB:
      TransportClassification(value: .usb, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeFireWire:
      TransportClassification(value: .fireWire, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeBluetooth:
      TransportClassification(value: .bluetooth, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeBluetoothLE:
      TransportClassification(value: .bluetoothLE, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeHDMI:
      TransportClassification(value: .hdmi, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeDisplayPort:
      TransportClassification(value: .displayPort, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeAirPlay:
      TransportClassification(value: .airPlay, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeAVB:
      TransportClassification(value: .avb, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeThunderbolt:
      TransportClassification(value: .thunderbolt, isContinuity: false, isUnrecognized: false)
    case kAudioDeviceTransportTypeContinuityCaptureWired,
      kAudioDeviceTransportTypeContinuityCaptureWireless,
      legacyContinuityCaptureTransport:
      TransportClassification(value: .unknown, isContinuity: true, isUnrecognized: false)
    default:
      TransportClassification(value: .unknown, isContinuity: false, isUnrecognized: true)
    }
  }

  private static func autofocus(
    _ rawValue: Int,
    malformed count: inout Int
  ) -> CameraInventoryAutofocusSystem {
    switch rawValue {
    case 0: return .none
    case 1: return .contrastDetection
    case 2: return .phaseDetection
    default:
      count += 1
      return .unknown
    }
  }

  private static func colorSpaces(
    _ rawValues: [Int],
    malformed count: inout Int
  ) -> [CameraInventoryColorSpace] {
    var values: [CameraInventoryColorSpace] = []
    for rawValue in rawValues {
      let value: CameraInventoryColorSpace
      switch rawValue {
      case 0: value = .sRGB
      case 1: value = .p3D65
      default:
        count += 1
        value = .unknown
      }
      if !values.contains(value) { values.append(value) }
    }
    return values.sorted { colorSpaceRank($0) < colorSpaceRank($1) }
  }

  private static func colorSpaceRank(_ value: CameraInventoryColorSpace) -> Int {
    switch value {
    case .sRGB: 0
    case .p3D65: 1
    case .unknown: 2
    }
  }

  private static func dimension(
    _ rawValue: Int64,
    malformed count: inout Int
  ) -> Int? {
    guard rawValue >= 1, rawValue <= Int64(maximumDimension) else {
      count += 1
      return nil
    }
    return Int(rawValue)
  }

  private static func frameRateRange(
    _ raw: CameraInventoryRawFrameRateRange,
    malformed count: inout Int
  ) -> (minimum: Double, maximum: Double)? {
    guard raw.minimum.isFinite, raw.maximum.isFinite,
      raw.minimum > 0, raw.maximum > 0,
      raw.minimum <= raw.maximum,
      raw.maximum <= maximumFrameRate
    else {
      count += 1
      return nil
    }
    return (raw.minimum, raw.maximum)
  }
}
