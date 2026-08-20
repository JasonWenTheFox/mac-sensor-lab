import CoreGraphics
import Foundation

struct PublicDisplayModeReading: Equatable, Sendable {
  let pixelWidth: Int
  let pixelHeight: Int
  let pointWidth: Int?
  let pointHeight: Int?
  let refreshRate: Double?
}

enum PublicDisplayMeasurements {
  private static let validDimensionRange = 1...100_000

  static func validDimension(_ value: Int?) -> Int? {
    guard let value, validDimensionRange.contains(value) else { return nil }
    return value
  }

  static func backingScale(
    pixelWidth: Int,
    pixelHeight: Int,
    pointWidth: Int,
    pointHeight: Int
  ) -> Double? {
    guard
      let pixelWidth = validDimension(pixelWidth),
      let pixelHeight = validDimension(pixelHeight),
      let pointWidth = validDimension(pointWidth),
      let pointHeight = validDimension(pointHeight)
    else { return nil }

    let horizontal = Double(pixelWidth) / Double(pointWidth)
    let vertical = Double(pixelHeight) / Double(pointHeight)
    guard
      horizontal.isFinite,
      vertical.isFinite,
      (0.5...8).contains(horizontal),
      (0.5...8).contains(vertical),
      abs(horizontal - vertical) <= max(0.01, max(horizontal, vertical) * 0.01)
    else { return nil }
    return (horizontal + vertical) / 2
  }

  static func validRefreshRate(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (1...1_000).contains(value) else { return nil }
    return value
  }
}

public struct DisplayProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "display.active",
    name: "Display",
    category: .display,
    source: "CoreGraphics",
    capability: .publicAPI
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    var count: UInt32 = 0
    let countResult = CGGetActiveDisplayList(0, nil, &count)
    guard countResult == .success, count > 0 else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "No active display detected",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability
      )
    }

    let main = CGMainDisplayID()
    let mode = CGDisplayCopyDisplayMode(main)
    let reading = PublicDisplayModeReading(
      pixelWidth: mode?.pixelWidth ?? CGDisplayPixelsWide(main),
      pixelHeight: mode?.pixelHeight ?? CGDisplayPixelsHigh(main),
      pointWidth: mode?.width,
      pointHeight: mode?.height,
      refreshRate: mode?.refreshRate
    )
    return snapshot(displayCount: count, reading: reading)
  }

  func snapshot(displayCount: UInt32, reading: PublicDisplayModeReading) -> SensorSnapshot {
    var channels = [
      SensorChannel(
        id: "display_count", label: "Active displays", value: Double(displayCount),
        formattedValue: "\(displayCount)"
      )
    ]
    let pixelWidth = PublicDisplayMeasurements.validDimension(reading.pixelWidth)
    let pixelHeight = PublicDisplayMeasurements.validDimension(reading.pixelHeight)
    let pointWidth = PublicDisplayMeasurements.validDimension(reading.pointWidth)
    let pointHeight = PublicDisplayMeasurements.validDimension(reading.pointHeight)

    if let pixelWidth, let pixelHeight {
      channels.append(
        SensorChannel(
          id: "main_resolution", label: "Main display pixels",
          formattedValue: "\(pixelWidth) × \(pixelHeight)", unit: "pixels"
        )
      )
    }
    if let pointWidth, let pointHeight {
      channels.append(
        SensorChannel(
          id: "main_logical_resolution", label: "Main display logical size",
          formattedValue: "\(pointWidth) × \(pointHeight)", unit: "points"
        )
      )
    }
    if let pixelWidth, let pixelHeight, let pointWidth, let pointHeight,
      let scale = PublicDisplayMeasurements.backingScale(
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        pointWidth: pointWidth,
        pointHeight: pointHeight
      )
    {
      channels.append(
        SensorChannel(
          id: "backing_scale", label: "Backing scale", value: scale,
          formattedValue: SensorFormatting.decimal(scale, fractionDigits: 2), unit: "×",
          kind: .derived
        )
      )
    }
    if let refresh = PublicDisplayMeasurements.validRefreshRate(reading.refreshRate) {
      channels.append(
        SensorChannel(
          id: "refresh_rate", label: "Refresh rate", value: refresh,
          formattedValue: SensorFormatting.decimal(refresh, fractionDigits: 1), unit: "Hz"
        )
      )
    }

    let summary: String
    if let pixelWidth, let pixelHeight {
      summary = "\(pixelWidth) × \(pixelHeight) px • \(displayCount) active"
    } else {
      summary = "\(displayCount) active displays"
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
        "Pixel and point dimensions are the current display mode; scale is derived. Persistent display identifiers are intentionally omitted."
      ]
    )
  }
}
