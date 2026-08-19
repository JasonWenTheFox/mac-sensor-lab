import Foundation
import IOKit.hid

/// Ordinary-permission, one-shot lid-angle probe.
///
/// The HID matching and feature-report approach is adapted from
/// samhenrigold/LidAngleSensor (Apache-2.0), commit
/// f7e4e5cb46fe13a518091ce5d47f0ec2e3fecd80.
/// This file is a modified implementation with project-specific safety and
/// error-reporting behavior.
public struct LidAngleProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "motion.lid_angle",
    name: "Lid Angle",
    category: .motion,
    source: "IOKit HID feature report",
    capability: .undocumented
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, noOptions)
    guard IOHIDManagerOpen(manager, noOptions) == kIOReturnSuccess else {
      return failure(status: .permissionRequired, summary: "HID manager could not be opened")
    }
    defer { IOHIDManagerClose(manager, noOptions) }

    let matching: [String: Any] = [
      kIOHIDVendorIDKey as String: 0x05AC,
      kIOHIDProductIDKey as String: 0x8104,
      "UsagePage": 0x0020,
      "Usage": 0x008A,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
      !devices.isEmpty
    else {
      return failure(status: .unavailable, summary: "Standard lid-angle HID interface not found")
    }

    var lastOpenError: IOReturn?
    for device in devices {
      let openResult = IOHIDDeviceOpen(device, noOptions)
      guard openResult == kIOReturnSuccess else {
        lastOpenError = openResult
        continue
      }

      var report = [UInt8](repeating: 0, count: 8)
      var length = CFIndex(report.count)
      let readResult = IOHIDDeviceGetReport(
        device,
        kIOHIDReportTypeFeature,
        1,
        &report,
        &length
      )
      IOHIDDeviceClose(device, noOptions)

      guard readResult == kIOReturnSuccess, length >= 3 else {
        continue
      }

      let raw = UInt16(report[2]) << 8 | UInt16(report[1])
      let angle = Double(raw & 0x01FF)
      guard (0...360).contains(angle) else {
        return failure(status: .degraded, summary: "Lid sensor returned an out-of-range value")
      }

      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "\(SensorFormatting.decimal(angle, fractionDigits: 1))°",
        status: .available,
        source: metadata.source,
        capability: metadata.capability,
        channels: [
          SensorChannel(
            id: "angle",
            label: "Opening angle",
            value: angle,
            formattedValue: SensorFormatting.decimal(angle, fractionDigits: 1),
            unit: "°",
            note: "Undocumented hardware interface; model-specific validation is required."
          )
        ],
        notes: ["No driver state was changed and no privileged access was attempted."]
      )
    }

    if let lastOpenError {
      return failure(
        status: .permissionRequired,
        summary: "Lid sensor detected but could not be opened",
        note: "IOReturn \(lastOpenError)"
      )
    }
    return failure(status: .degraded, summary: "Lid sensor did not return a feature report")
  }

  private func failure(status: SensorStatus, summary: String, note: String? = nil) -> SensorSnapshot
  {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: status,
      source: metadata.source,
      capability: metadata.capability,
      notes: [note, "The App will not request sudo or alter HID driver properties."].compactMap {
        $0
      }
    )
  }
}
