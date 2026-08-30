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
    let managerOpenResult = IOHIDManagerOpen(manager, noOptions)
    guard managerOpenResult == kIOReturnSuccess else {
      return openFailure(results: [managerOpenResult])
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

    var openErrors: [IOReturn] = []
    for device in devices {
      let openResult = IOHIDDeviceOpen(device, noOptions)
      guard openResult == kIOReturnSuccess else {
        openErrors.append(openResult)
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
        notes: []
      )
    }

    if !openErrors.isEmpty { return openFailure(results: openErrors) }
    return failure(status: .degraded, summary: "Lid sensor did not return a feature report")
  }

  private func openFailure(results: [IOReturn]) -> SensorSnapshot {
    let status = SPUHIDOpenFailure.status(for: results)
    let summary =
      switch status {
      case .permissionRequired: "macOS denied access to the lid-angle sensor"
      case .degraded: "The lid-angle sensor is temporarily busy"
      case .unavailable: "The lid-angle sensor is not available on this Mac"
      default: "The lid-angle sensor could not be opened"
      }
    return failure(status: status, summary: summary)
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
      notes: [note].compactMap { $0 }
    )
  }
}
