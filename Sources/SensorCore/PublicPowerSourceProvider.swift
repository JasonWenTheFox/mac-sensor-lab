import Foundation
import IOKit.ps

enum PublicPowerSourceKind: Equatable, Sendable {
  case ac
  case battery
  case ups

  init?(systemValue: String?) {
    switch systemValue {
    case kIOPMACPowerKey: self = .ac
    case kIOPMBatteryPowerKey: self = .battery
    case kIOPMUPSPowerKey: self = .ups
    default: return nil
    }
  }

  var displayName: String {
    switch self {
    case .ac: "AC power"
    case .battery: "Battery"
    case .ups: "UPS power"
    }
  }
}

enum PublicBatteryWarning: Equatable, Sendable {
  case none
  case early
  case final

  init?(systemValue: IOPSLowBatteryWarningLevel) {
    switch systemValue {
    case kIOPSLowBatteryWarningNone: self = .none
    case kIOPSLowBatteryWarningEarly: self = .early
    case kIOPSLowBatteryWarningFinal: self = .final
    default: return nil
    }
  }

  var displayName: String {
    switch self {
    case .none: "No warning"
    case .early: "Early warning"
    case .final: "Final warning"
    }
  }
}

struct PublicPowerSourceReading: Equatable, Sendable {
  let source: PublicPowerSourceKind?
  let batteryWarning: PublicBatteryWarning?
  let currentCapacity: Double?
  let maximumCapacity: Double?
  let isCharging: Bool?
  let timeToEmptyMinutes: Double?
  let timeToFullMinutes: Double?
  let systemTimeRemainingSeconds: Double?
}

enum PublicPowerSourceMeasurements {
  static func chargePercentage(current: Double?, maximum: Double?) -> Double? {
    guard let current, let maximum,
      current.isFinite, maximum.isFinite,
      current >= 0, maximum > 0, current <= maximum,
      current <= 100, maximum <= 100
    else { return nil }
    let percentage = current / maximum * 100
    guard percentage.isFinite, (0...100).contains(percentage) else { return nil }
    return percentage
  }

  static func validMinutes(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (0...1_440).contains(value) else { return nil }
    return value
  }

  static func validSystemMinutes(seconds: Double?) -> Double? {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
    return validMinutes(seconds / 60)
  }
}

public struct PublicPowerSourceProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "power.source",
    name: "System Power Source",
    category: .power,
    source: "IOKit IOPowerSources",
    capability: .publicAPI
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
      return unavailableSnapshot(summary: "Public power-source information was unavailable")
    }

    let sourceValue = IOPSGetProvidingPowerSourceType(info)
      .map { $0.takeUnretainedValue() as String }
    let battery = internalBatteryDescription(info: info)
    let reading = PublicPowerSourceReading(
      source: PublicPowerSourceKind(systemValue: sourceValue),
      batteryWarning: PublicBatteryWarning(systemValue: IOPSGetBatteryWarningLevel()),
      currentCapacity: number(battery, key: kIOPSCurrentCapacityKey),
      maximumCapacity: number(battery, key: kIOPSMaxCapacityKey),
      isCharging: boolean(battery, key: kIOPSIsChargingKey),
      timeToEmptyMinutes: number(battery, key: kIOPSTimeToEmptyKey),
      timeToFullMinutes: number(battery, key: kIOPSTimeToFullChargeKey),
      systemTimeRemainingSeconds: IOPSGetTimeRemainingEstimate()
    )
    return snapshot(reading: reading)
  }

  func snapshot(reading: PublicPowerSourceReading) -> SensorSnapshot {
    var channels: [SensorChannel] = []
    if let source = reading.source {
      channels.append(
        SensorChannel(
          id: "active_source",
          label: "Active power source",
          formattedValue: source.displayName
        )
      )
    }

    let charge = PublicPowerSourceMeasurements.chargePercentage(
      current: reading.currentCapacity,
      maximum: reading.maximumCapacity
    )
    if let charge {
      channels.append(
        SensorChannel(
          id: "battery_charge",
          label: "Battery charge (public API)",
          value: charge,
          formattedValue: SensorFormatting.percentage(charge),
          unit: "%",
          kind: .derived,
          note: "Current Capacity ÷ Max Capacity from Apple's public power-source API."
        )
      )
    }
    if let isCharging = reading.isCharging {
      channels.append(
        SensorChannel(
          id: "battery_charging",
          label: "Battery charging (public API)",
          value: isCharging ? 1 : 0,
          formattedValue: isCharging ? "Yes" : "No"
        )
      )
    }
    if let batteryWarning = reading.batteryWarning {
      channels.append(
        SensorChannel(
          id: "battery_warning",
          label: "System low-battery warning",
          formattedValue: batteryWarning.displayName,
          note: "Operating-system warning level; time thresholds are estimates, not guarantees."
        )
      )
    }
    if let minutes = PublicPowerSourceMeasurements.validSystemMinutes(
      seconds: reading.systemTimeRemainingSeconds
    ) {
      channels.append(
        estimatedMinutesChannel(
          id: "system_time_remaining",
          label: "System time remaining",
          value: minutes,
          note: "System-wide IOPowerSources estimate for the active limited power source."
        )
      )
    }
    if reading.source == .battery, reading.isCharging != true,
      let minutes = PublicPowerSourceMeasurements.validMinutes(reading.timeToEmptyMinutes)
    {
      channels.append(
        estimatedMinutesChannel(
          id: "battery_time_to_empty",
          label: "Battery time to empty (public API)",
          value: minutes,
          note: "Battery-specific operating-system estimate; calculating sentinels are omitted."
        )
      )
    }
    if reading.isCharging == true,
      let minutes = PublicPowerSourceMeasurements.validMinutes(reading.timeToFullMinutes)
    {
      channels.append(
        estimatedMinutesChannel(
          id: "battery_time_to_full",
          label: "Battery time to full (public API)",
          value: minutes,
          note: "Battery-specific operating-system estimate; calculating sentinels are omitted."
        )
      )
    }

    guard !channels.isEmpty else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Public power-source information returned no allowlisted values",
        status: .degraded,
        source: metadata.source,
        capability: metadata.capability,
        notes: privacyNotes
      )
    }

    let summary: String
    switch (charge, reading.source) {
    case (.some(let charge), .some(let source)):
      summary = "\(SensorFormatting.percentage(charge)) • \(source.displayName)"
    case (.some(let charge), .none):
      summary = SensorFormatting.percentage(charge)
    case (.none, .some(let source)):
      summary = source.displayName
    case (.none, .none):
      summary = "Public power-source information available"
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
      notes: privacyNotes
    )
  }

  private var privacyNotes: [String] {
    [
      "Uses Apple's public IOPowerSources API.",
      "Power-source names, IDs, serial numbers, transport details, and adapter metadata are intentionally ignored.",
      "Time remaining values are operating-system estimates.",
    ]
  }

  private func unavailableSnapshot(summary: String) -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: .unavailable,
      source: metadata.source,
      capability: metadata.capability,
      notes: privacyNotes
    )
  }

  private func internalBatteryDescription(info: CFTypeRef) -> NSDictionary? {
    guard
      let sourceHandles = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }

    for sourceHandle in sourceHandles {
      guard
        let description = IOPSGetPowerSourceDescription(info, sourceHandle)?
          .takeUnretainedValue() as NSDictionary?,
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
      else { continue }
      return description
    }
    return nil
  }

  private func number(_ dictionary: NSDictionary?, key: String) -> Double? {
    guard let value = dictionary?[key], CFGetTypeID(value as CFTypeRef) == CFNumberGetTypeID()
    else { return nil }
    return (value as? NSNumber)?.doubleValue
  }

  private func boolean(_ dictionary: NSDictionary?, key: String) -> Bool? {
    guard let value = dictionary?[key], CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    else { return nil }
    return (value as? NSNumber)?.boolValue
  }

  private func estimatedMinutesChannel(
    id: String,
    label: String,
    value: Double,
    note: String
  ) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: value,
      formattedValue: SensorFormatting.decimal(value, fractionDigits: 0),
      unit: "minutes",
      kind: .estimated,
      note: note
    )
  }
}
