import CoreGraphics
import Foundation

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
    let width = CGDisplayPixelsWide(main)
    let height = CGDisplayPixelsHigh(main)
    let refresh = CGDisplayCopyDisplayMode(main)?.refreshRate ?? 0
    var channels = [
      SensorChannel(
        id: "display_count", label: "Active displays", value: Double(count),
        formattedValue: "\(count)"),
      SensorChannel(
        id: "main_resolution", label: "Main display (logical)",
        formattedValue: "\(width) × \(height)", unit: "pixels"),
    ]
    if refresh > 0 {
      channels.append(
        SensorChannel(
          id: "refresh_rate", label: "Refresh rate", value: refresh,
          formattedValue: SensorFormatting.decimal(refresh, fractionDigits: 1), unit: "Hz"))
    }

    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "\(width) × \(height) • \(count) active",
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: [
        "Resolution is the current logical mode. Persistent display identifiers are intentionally omitted."
      ]
    )
  }
}
