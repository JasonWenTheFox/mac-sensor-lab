import AppKit
import CoreGraphics
import DiskArbitration
import Foundation

struct DisplayHardwareReading: Equatable, Sendable {
  let isMain: Bool
  let isBuiltIn: Bool
  let currentPixelWidth: Int?
  let currentPixelHeight: Int?
  let currentPointWidth: Int?
  let currentPointHeight: Int?
  let supportedModeCount: Int?
  let maximumPixelWidth: Int?
  let maximumPixelHeight: Int?
  let maximumFramesPerSecond: Int?
  let variableRefreshRate: Bool?
  let colorSpaceModel: String?
  let wideColorGamut: Bool?
  let maximumPotentialEDRHeadroom: Double?
  let physicalWidthMillimeters: Double?
  let physicalHeightMillimeters: Double?
}

enum DisplayHardwareMeasurements {
  static let maximumDisplayCount = 16

  static func dimension(_ value: Int?) -> Int? {
    guard let value, (1...100_000).contains(value) else { return nil }
    return value
  }

  static func modeCount(_ value: Int?) -> Int? {
    guard let value, (1...4_096).contains(value) else { return nil }
    return value
  }

  static func framesPerSecond(_ value: Int?) -> Int? {
    guard let value, (1...1_000).contains(value) else { return nil }
    return value
  }

  static func millimeters(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (10...10_000).contains(value) else { return nil }
    return value
  }

  static func edrHeadroom(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (1...100).contains(value) else { return nil }
    return value
  }

  static func diagonalInches(widthMillimeters: Double?, heightMillimeters: Double?) -> Double? {
    guard
      let width = millimeters(widthMillimeters),
      let height = millimeters(heightMillimeters)
    else { return nil }
    let diagonal = hypot(width, height) / 25.4
    guard diagonal.isFinite, (1...1_000).contains(diagonal) else { return nil }
    return diagonal
  }

  static func pixelsPerInch(
    pixelWidth: Int?,
    pixelHeight: Int?,
    widthMillimeters: Double?,
    heightMillimeters: Double?
  ) -> Double? {
    guard
      let pixelWidth = dimension(pixelWidth),
      let pixelHeight = dimension(pixelHeight),
      let diagonalInches = diagonalInches(
        widthMillimeters: widthMillimeters,
        heightMillimeters: heightMillimeters
      )
    else { return nil }
    let pixels = hypot(Double(pixelWidth), Double(pixelHeight))
    let ppi = pixels / diagonalInches
    guard ppi.isFinite, (10...2_000).contains(ppi) else { return nil }
    return ppi
  }

  static func maximumPixelDimensions(
    currentWidth: Int?,
    currentHeight: Int?,
    enumeratedWidth: Int?,
    enumeratedHeight: Int?
  ) -> (width: Int, height: Int)? {
    let candidates = [
      (dimension(currentWidth), dimension(currentHeight)),
      (dimension(enumeratedWidth), dimension(enumeratedHeight)),
    ].compactMap { width, height -> (width: Int, height: Int)? in
      guard let width, let height else { return nil }
      return (width, height)
    }
    return candidates.max { lhs, rhs in
      let leftArea = lhs.width * lhs.height
      let rightArea = rhs.width * rhs.height
      return leftArea == rightArea ? lhs.width < rhs.width : leftArea < rightArea
    }
  }
}

private struct DisplayModeSignature: Hashable {
  let pixelWidth: Int
  let pixelHeight: Int
  let pointWidth: Int
  let pointHeight: Int
  let refreshRateTenths: Int
}

@MainActor
private enum DisplayHardwareReader {
  static func read() -> [DisplayHardwareReading] {
    var displayCount: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
      displayCount > 0,
      displayCount <= DisplayHardwareMeasurements.maximumDisplayCount
    else { return [] }

    var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    var actualCount: UInt32 = 0
    guard
      CGGetActiveDisplayList(displayCount, &displayIDs, &actualCount) == .success,
      actualCount > 0,
      actualCount <= displayCount
    else { return [] }
    displayIDs = Array(displayIDs.prefix(Int(actualCount)))

    let mainDisplayID = CGMainDisplayID()
    displayIDs.sort { lhs, rhs in
      if lhs == mainDisplayID { return rhs != mainDisplayID }
      if rhs == mainDisplayID { return false }
      let left = CGDisplayBounds(lhs)
      let right = CGDisplayBounds(rhs)
      let leftPosition = (left.minX, left.minY, left.width, left.height)
      let rightPosition = (right.minX, right.minY, right.width, right.height)
      if leftPosition != rightPosition {
        return leftPosition < rightPosition
      }
      return lhs < rhs
    }

    let appKitScreensByID: [CGDirectDisplayID: NSScreen]
    if NSApp == nil {
      appKitScreensByID = [:]
    } else {
      appKitScreensByID = Dictionary(
        uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
          guard
            let number = screen.deviceDescription[
              NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
          else { return nil }
          return (CGDirectDisplayID(number.uint32Value), screen)
        }
      )
    }

    return displayIDs.map { displayID in
      let currentMode = CGDisplayCopyDisplayMode(displayID)
      let modeSummary = summarizedModes(for: displayID)
      let maximumPixels = DisplayHardwareMeasurements.maximumPixelDimensions(
        currentWidth: currentMode?.pixelWidth,
        currentHeight: currentMode?.pixelHeight,
        enumeratedWidth: modeSummary.maximumWidth,
        enumeratedHeight: modeSummary.maximumHeight
      )
      let screen = appKitScreensByID[displayID]
      let physicalSize = CGDisplayScreenSize(displayID)
      let colorSpaceModel = colorSpaceName(CGDisplayCopyColorSpace(displayID).model)
      let refreshIntervals = screen.flatMap { screen -> (Double, Double)? in
        let minimum = screen.minimumRefreshInterval
        let maximum = screen.maximumRefreshInterval
        guard minimum.isFinite, maximum.isFinite, minimum > 0, maximum > 0 else {
          return nil
        }
        return (minimum, maximum)
      }
      return DisplayHardwareReading(
        isMain: displayID == mainDisplayID,
        isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
        currentPixelWidth: currentMode?.pixelWidth,
        currentPixelHeight: currentMode?.pixelHeight,
        currentPointWidth: currentMode?.width,
        currentPointHeight: currentMode?.height,
        supportedModeCount: modeSummary.count,
        maximumPixelWidth: maximumPixels?.width,
        maximumPixelHeight: maximumPixels?.height,
        maximumFramesPerSecond: screen?.maximumFramesPerSecond,
        variableRefreshRate: refreshIntervals.map { abs($0.0 - $0.1) > 0.000_001 },
        colorSpaceModel: colorSpaceModel,
        wideColorGamut: screen.map { $0.canRepresent(.p3) },
        maximumPotentialEDRHeadroom: screen.map {
          Double($0.maximumPotentialExtendedDynamicRangeColorComponentValue)
        },
        physicalWidthMillimeters: Double(physicalSize.width),
        physicalHeightMillimeters: Double(physicalSize.height)
      )
    }
  }

  private static func summarizedModes(
    for displayID: CGDirectDisplayID
  ) -> (count: Int?, maximumWidth: Int?, maximumHeight: Int?) {
    guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode]
    else { return (nil, nil, nil) }
    var signatures = Set<DisplayModeSignature>()
    var maximum: (width: Int, height: Int)?
    for mode in modes {
      guard
        let pixelWidth = DisplayHardwareMeasurements.dimension(mode.pixelWidth),
        let pixelHeight = DisplayHardwareMeasurements.dimension(mode.pixelHeight),
        let pointWidth = DisplayHardwareMeasurements.dimension(mode.width),
        let pointHeight = DisplayHardwareMeasurements.dimension(mode.height)
      else { continue }
      let refresh =
        mode.refreshRate.isFinite && mode.refreshRate >= 0
        ? Int((mode.refreshRate * 10).rounded()) : 0
      signatures.insert(
        DisplayModeSignature(
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
          pointWidth: pointWidth,
          pointHeight: pointHeight,
          refreshRateTenths: refresh
        )
      )
      let shouldReplaceMaximum: Bool
      if let maximum {
        shouldReplaceMaximum =
          pixelWidth * pixelHeight > maximum.width * maximum.height
          || (pixelWidth * pixelHeight == maximum.width * maximum.height
            && pixelWidth > maximum.width)
      } else {
        shouldReplaceMaximum = true
      }
      if shouldReplaceMaximum {
        maximum = (pixelWidth, pixelHeight)
      }
    }
    return (
      DisplayHardwareMeasurements.modeCount(signatures.count),
      maximum?.width,
      maximum?.height
    )
  }

  private static func colorSpaceName(_ model: CGColorSpaceModel) -> String? {
    switch model {
    case .monochrome: "Monochrome"
    case .rgb: "RGB"
    case .cmyk: "CMYK"
    case .lab: "Lab"
    case .deviceN: "DeviceN"
    case .indexed: "Indexed"
    case .pattern: "Pattern"
    case .XYZ: "XYZ"
    case .unknown: nil
    @unknown default: nil
    }
  }
}

public struct DisplayHardwareProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "hardware.display",
    name: "Display Hardware",
    category: .display,
    source: "CoreGraphics and AppKit display capabilities",
    capability: .publicAPI,
    domain: .display,
    accessLevel: .publicOrdinary,
    compatibilityConfidence: .documentedPlatformContract
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let readings = await DisplayHardwareReader.read()
    return snapshot(readings: readings)
  }

  func snapshot(readings: [DisplayHardwareReading]) -> SensorSnapshot {
    let readings = Array(readings.prefix(DisplayHardwareMeasurements.maximumDisplayCount))
    guard !readings.isEmpty else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Display hardware capabilities were unavailable",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability,
        notes: ["No display identifiers, localized names, EDID blobs, or serial numbers are read."]
      )
    }

    var channels = [integerChannel("display_count", "Active display hardware", readings.count)]
    var edrCapableCount = 0
    var edrObservationCount = 0
    for (index, reading) in readings.enumerated() {
      let slot = "display_\(index + 1)"
      channels.append(
        booleanChannel("\(slot)_main", "Display \(index + 1) is main", reading.isMain))
      channels.append(
        booleanChannel("\(slot)_built_in", "Display \(index + 1) is built in", reading.isBuiltIn)
      )
      if let width = DisplayHardwareMeasurements.dimension(reading.currentPixelWidth),
        let height = DisplayHardwareMeasurements.dimension(reading.currentPixelHeight)
      {
        channels.append(
          textChannel(
            "\(slot)_current_pixels", "Display \(index + 1) current pixels",
            "\(width) × \(height)", unit: "pixels"
          )
        )
      }
      if let width = DisplayHardwareMeasurements.dimension(reading.currentPointWidth),
        let height = DisplayHardwareMeasurements.dimension(reading.currentPointHeight)
      {
        channels.append(
          textChannel(
            "\(slot)_current_points", "Display \(index + 1) current logical size",
            "\(width) × \(height)", unit: "points"
          )
        )
      }
      if let count = DisplayHardwareMeasurements.modeCount(reading.supportedModeCount) {
        channels.append(
          integerChannel("\(slot)_mode_count", "Display \(index + 1) available modes", count)
        )
      }
      if let width = DisplayHardwareMeasurements.dimension(reading.maximumPixelWidth),
        let height = DisplayHardwareMeasurements.dimension(reading.maximumPixelHeight)
      {
        channels.append(
          textChannel(
            "\(slot)_maximum_mode_pixels", "Display \(index + 1) maximum mode pixels",
            "\(width) × \(height)", unit: "pixels"
          )
        )
      }
      if let fps = DisplayHardwareMeasurements.framesPerSecond(reading.maximumFramesPerSecond) {
        channels.append(
          integerChannel(
            "\(slot)_maximum_frame_rate", "Display \(index + 1) maximum frame rate", fps,
            unit: "Hz"
          )
        )
      }
      if let variableRefreshRate = reading.variableRefreshRate {
        channels.append(
          booleanChannel(
            "\(slot)_variable_refresh", "Display \(index + 1) variable refresh",
            variableRefreshRate
          )
        )
      }
      if let colorSpaceModel = reading.colorSpaceModel,
        ["Monochrome", "RGB", "CMYK", "Lab", "DeviceN", "Indexed", "Pattern", "XYZ"]
          .contains(colorSpaceModel)
      {
        channels.append(
          textChannel(
            "\(slot)_color_space_model", "Display \(index + 1) color space model",
            colorSpaceModel
          )
        )
      }
      if let wideColorGamut = reading.wideColorGamut {
        channels.append(
          booleanChannel(
            "\(slot)_wide_color_gamut", "Display \(index + 1) Display P3 gamut",
            wideColorGamut
          )
        )
      }
      if let headroom = DisplayHardwareMeasurements.edrHeadroom(
        reading.maximumPotentialEDRHeadroom
      ) {
        edrObservationCount += 1
        let supportsEDR = headroom > 1
        if supportsEDR { edrCapableCount += 1 }
        channels.append(
          booleanChannel(
            "\(slot)_edr_supported", "Display \(index + 1) EDR capability", supportsEDR,
            kind: .derived
          )
        )
        channels.append(
          numberChannel(
            "\(slot)_maximum_edr_headroom", "Display \(index + 1) maximum EDR headroom",
            headroom, unit: "×"
          )
        )
      }
      if let width = DisplayHardwareMeasurements.millimeters(
        reading.physicalWidthMillimeters
      ),
        let height = DisplayHardwareMeasurements.millimeters(
          reading.physicalHeightMillimeters
        )
      {
        channels.append(
          numberChannel(
            "\(slot)_physical_width", "Display \(index + 1) reported physical width", width,
            unit: "mm", kind: .estimated
          )
        )
        channels.append(
          numberChannel(
            "\(slot)_physical_height", "Display \(index + 1) reported physical height", height,
            unit: "mm", kind: .estimated
          )
        )
        if let diagonal = DisplayHardwareMeasurements.diagonalInches(
          widthMillimeters: width,
          heightMillimeters: height
        ) {
          channels.append(
            numberChannel(
              "\(slot)_diagonal", "Display \(index + 1) estimated diagonal", diagonal,
              unit: "in", kind: .estimated
            )
          )
        }
        if let ppi = DisplayHardwareMeasurements.pixelsPerInch(
          pixelWidth: reading.currentPixelWidth,
          pixelHeight: reading.currentPixelHeight,
          widthMillimeters: width,
          heightMillimeters: height
        ) {
          channels.append(
            numberChannel(
              "\(slot)_ppi", "Display \(index + 1) estimated pixel density", ppi,
              unit: "ppi", kind: .estimated
            )
          )
        }
      }
    }
    if edrObservationCount == readings.count {
      channels.insert(
        integerChannel(
          "edr_capable_count", "EDR-capable displays", edrCapableCount, kind: .derived
        ),
        at: 1
      )
    }
    let summary =
      edrObservationCount == readings.count
      ? "\(readings.count) active • \(edrCapableCount) EDR capable"
      : "\(readings.count) active displays"
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
        "Display slots are session-local order labels, not persistent identifiers.",
        "CoreGraphics may estimate physical size at 72 DPI when EDID is unavailable, so physical dimensions and PPI remain Estimated.",
        "Localized display names, display IDs, EDID data, ICC profile names, and serial numbers are intentionally omitted.",
      ]
    )
  }
}

struct StorageHardwareReading: Equatable, Sendable {
  let protocolClass: String?
  let isInternal: Bool?
  let isRemovable: Bool?
  let isEjectable: Bool?
  let isWritable: Bool?
  let mediaSize: UInt64?
  let blockSize: UInt64?
  let partitionScheme: String?
}

enum StorageHardwareSanitizer {
  static func protocolClass(_ value: String?) -> String? {
    guard let value = boundedASCII(value, maximumBytes: 64) else { return nil }
    let lowercased = value.lowercased()
    if lowercased.contains("nvme") { return "NVMe" }
    if lowercased.contains("thunderbolt") { return "Thunderbolt" }
    if lowercased.contains("usb") { return "USB" }
    if lowercased.contains("firewire") { return "FireWire" }
    if lowercased.contains("sata") || lowercased == "ata" { return "SATA/ATA" }
    if lowercased.contains("pci") { return "PCI" }
    if lowercased.contains("virtual") { return "Virtual" }
    return nil
  }

  static func partitionScheme(_ value: String?) -> String? {
    switch value {
    case "GUID_partition_scheme": "GUID partition map"
    case "FDisk_partition_scheme": "MBR partition map"
    case "Apple_partition_scheme": "Apple partition map"
    case "Apple_APFS": "APFS container"
    default: nil
    }
  }

  static func mediaSize(_ value: UInt64?) -> UInt64? {
    // SensorChannel stores numeric values as Double. Keep byte counts inside the
    // largest exactly representable integer so JSON/CSV raw values stay truthful.
    guard let value, (1_048_576...9_007_199_254_740_992).contains(value) else {
      return nil
    }
    return value
  }

  static func blockSize(_ value: UInt64?) -> UInt64? {
    guard let value, (1...1_048_576).contains(value) else { return nil }
    return value
  }

  private static func boundedASCII(_ value: String?, maximumBytes: Int) -> String? {
    guard let value,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty,
      value.utf8.count <= maximumBytes,
      value.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 0x20 && $0.value <= 0x7E })
    else { return nil }
    return value
  }
}

private enum StorageHardwareReader {
  static func read() -> StorageHardwareReading? {
    guard
      let session = DASessionCreate(kCFAllocatorDefault),
      let volumeDisk = DADiskCreateFromVolumePath(
        kCFAllocatorDefault,
        session,
        URL(fileURLWithPath: "/", isDirectory: true) as CFURL
      ),
      let wholeDisk = DADiskCopyWholeDisk(volumeDisk),
      let description = DADiskCopyDescription(wholeDisk) as NSDictionary?
    else { return nil }

    return StorageHardwareReading(
      protocolClass: StorageHardwareSanitizer.protocolClass(
        description[kDADiskDescriptionDeviceProtocolKey] as? String
      ),
      isInternal: boolean(description, key: kDADiskDescriptionDeviceInternalKey),
      isRemovable: boolean(description, key: kDADiskDescriptionMediaRemovableKey),
      isEjectable: boolean(description, key: kDADiskDescriptionMediaEjectableKey),
      isWritable: boolean(description, key: kDADiskDescriptionMediaWritableKey),
      mediaSize: StorageHardwareSanitizer.mediaSize(
        unsignedInteger(description, key: kDADiskDescriptionMediaSizeKey)
      ),
      blockSize: StorageHardwareSanitizer.blockSize(
        unsignedInteger(description, key: kDADiskDescriptionMediaBlockSizeKey)
      ),
      partitionScheme: StorageHardwareSanitizer.partitionScheme(
        description[kDADiskDescriptionMediaContentKey] as? String
      )
    )
  }

  private static func boolean(_ description: NSDictionary, key: CFString) -> Bool? {
    guard let value = description[key] as? NSNumber,
      CFGetTypeID(value) == CFBooleanGetTypeID()
    else { return nil }
    return value.boolValue
  }

  private static func unsignedInteger(_ description: NSDictionary, key: CFString) -> UInt64? {
    SensorNumericSafety.uint64(description[key] as? NSNumber)
  }
}

public struct StorageHardwareProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "hardware.storage",
    name: "System Storage Hardware",
    category: .storage,
    source: "Disk Arbitration whole-disk description",
    capability: .publicAPI,
    domain: .storage,
    accessLevel: .publicOrdinary,
    compatibilityConfidence: .documentedPlatformContract
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    snapshot(reading: StorageHardwareReader.read())
  }

  func snapshot(reading: StorageHardwareReading?) -> SensorSnapshot {
    guard let reading else {
      return unavailableSnapshot()
    }
    let protocolClass = StorageHardwareSanitizer.protocolClass(reading.protocolClass)
    let partitionScheme = StorageHardwareSanitizer.partitionScheme(reading.partitionScheme)
    var channels: [SensorChannel] = []
    if let protocolClass {
      channels.append(textChannel("protocol", "Storage protocol class", protocolClass))
    }
    if let isInternal = reading.isInternal {
      channels.append(booleanChannel("internal", "Internal storage", isInternal))
    }
    if let isRemovable = reading.isRemovable {
      channels.append(booleanChannel("removable", "Removable media", isRemovable))
    }
    if let isEjectable = reading.isEjectable {
      channels.append(booleanChannel("ejectable", "Ejectable media", isEjectable))
    }
    if let isWritable = reading.isWritable {
      channels.append(booleanChannel("writable", "Writable media", isWritable))
    }
    if let mediaSize = StorageHardwareSanitizer.mediaSize(reading.mediaSize) {
      channels.append(bytesChannel("media_size", "Reported media capacity", mediaSize))
    }
    if let blockSize = StorageHardwareSanitizer.blockSize(reading.blockSize) {
      channels.append(bytesChannel("block_size", "Media block size", blockSize))
    }
    if let partitionScheme {
      channels.append(
        textChannel("partition_scheme", "Partition scheme class", partitionScheme)
      )
    }
    guard !channels.isEmpty else { return unavailableSnapshot() }

    let summary: String
    if let protocolClass,
      let mediaSize = StorageHardwareSanitizer.mediaSize(reading.mediaSize)
    {
      summary = "\(protocolClass) • \(SensorFormatting.bytes(mediaSize))"
    } else if let protocolClass {
      summary = protocolClass
    } else if let mediaSize = StorageHardwareSanitizer.mediaSize(reading.mediaSize) {
      summary = SensorFormatting.bytes(mediaSize)
    } else {
      summary = "System storage facts available"
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
        "Only the whole-disk object associated with the current system volume is summarized.",
        "Device model, vendor, revision, serial number, GUID, UUID, BSD name, registry path, volume name, and mount path are intentionally omitted.",
        "SMART and NVMe health fields are not inferred from Disk Arbitration metadata.",
      ]
    )
  }

  private func unavailableSnapshot() -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "System storage hardware facts were unavailable",
      status: .unavailable,
      source: metadata.source,
      capability: metadata.capability,
      notes: ["No device path, identifier, model, or system error text is exported."]
    )
  }
}

private func integerChannel(
  _ id: String,
  _ label: String,
  _ value: Int,
  unit: String? = nil,
  kind: SensorValueKind = .raw
) -> SensorChannel {
  SensorChannel(
    id: id,
    label: label,
    value: Double(value),
    formattedValue: String(value),
    unit: unit,
    kind: kind
  )
}

private func numberChannel(
  _ id: String,
  _ label: String,
  _ value: Double,
  unit: String? = nil,
  kind: SensorValueKind = .raw
) -> SensorChannel {
  SensorChannel(
    id: id,
    label: label,
    value: value,
    formattedValue: SensorFormatting.decimal(value, fractionDigits: 2),
    unit: unit,
    kind: kind
  )
}

private func booleanChannel(
  _ id: String,
  _ label: String,
  _ value: Bool,
  kind: SensorValueKind = .raw
) -> SensorChannel {
  SensorChannel(
    id: id,
    label: label,
    value: value ? 1 : 0,
    formattedValue: value ? "Yes" : "No",
    kind: kind
  )
}

private func textChannel(
  _ id: String,
  _ label: String,
  _ value: String,
  unit: String? = nil,
  kind: SensorValueKind = .raw
) -> SensorChannel {
  SensorChannel(id: id, label: label, formattedValue: value, unit: unit, kind: kind)
}

private func bytesChannel(_ id: String, _ label: String, _ value: UInt64) -> SensorChannel {
  SensorChannel(
    id: id,
    label: label,
    value: Double(value),
    formattedValue: SensorFormatting.bytes(value),
    unit: "bytes"
  )
}
