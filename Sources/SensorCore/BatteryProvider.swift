import Foundation
import IOKit

enum BatteryMeasurements {
  static func chargePercentage(current: Double?, maximum: Double?) -> Double? {
    guard let current, let maximum,
      current.isFinite, maximum.isFinite,
      maximum > 0, current >= 0, current <= maximum
    else { return nil }
    let percentage = current / maximum * 100
    return percentage.isFinite ? percentage : nil
  }

  static func capacityRatio(nominal: Double, design: Double) -> Double? {
    guard nominal.isFinite, design.isFinite, nominal >= 0, design > 0 else { return nil }
    let ratio = nominal / design * 100
    return ratio.isFinite ? ratio : nil
  }

  static func validMinutes(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (0...1_440).contains(value) else { return nil }
    return value
  }

  static func electricalPower(voltage: Double?, current: Double?) -> Double? {
    guard let voltage, let current, voltage.isFinite, current.isFinite else { return nil }
    let power = voltage * current
    return power.isFinite ? power : nil
  }

  static func capacity(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
  }
}

public struct BatteryProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "power.battery",
    name: "Power & Battery",
    category: .power,
    source: "AppleSmartBattery IORegistry",
    capability: .undocumented
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let service = IOKitHelpers.matchingService("AppleSmartBattery")
    guard service != 0 else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "No internal battery detected",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability,
        notes: ["Desktop Macs may not expose AppleSmartBattery."]
      )
    }
    defer { IOObjectRelease(service) }

    let currentCapacity = IOKitHelpers.number(service, key: "CurrentCapacity")
    let maximum = IOKitHelpers.number(service, key: "MaxCapacity")
    let external = IOKitHelpers.bool(service, key: "ExternalConnected")
    let charging = IOKitHelpers.bool(service, key: "IsCharging")
    let fullyCharged = IOKitHelpers.bool(service, key: "FullyCharged")
    let cycles = IOKitHelpers.number(service, key: "CycleCount")
    let designCapacity = BatteryMeasurements.capacity(
      IOKitHelpers.number(service, key: "DesignCapacity"))
    let nominalCapacity = BatteryMeasurements.capacity(
      IOKitHelpers.number(service, key: "NominalChargeCapacity"))
    let timeRemaining = BatteryMeasurements.validMinutes(
      IOKitHelpers.number(service, key: "TimeRemaining"))
    let averageTimeToFull = BatteryMeasurements.validMinutes(
      IOKitHelpers.number(service, key: "AvgTimeToFull"))
    let voltageMillivolts = IOKitHelpers.number(service, key: "Voltage")
    let amperageMilliamps = IOKitHelpers.number(service, key: "Amperage")
    let temperatureRaw = IOKitHelpers.number(service, key: "Temperature")

    let percentage = BatteryMeasurements.chargePercentage(
      current: currentCapacity,
      maximum: maximum
    )
    let voltage = voltageMillivolts.flatMap { value -> Double? in
      guard value.isFinite, value > 0 else { return nil }
      return value / 1000
    }
    let currentAmps = amperageMilliamps.flatMap { value -> Double? in
      guard value.isFinite else { return nil }
      return value / 1000
    }
    let power = BatteryMeasurements.electricalPower(voltage: voltage, current: currentAmps)
    // AppleSmartBattery exposes Temperature in deci-kelvin (for example,
    // 3069 means 306.9 K, or roughly 33.8 °C).
    let temperature = temperatureRaw.map { $0 / 10 - 273.15 }

    var channels: [SensorChannel] = []
    if let percentage {
      channels.append(
        SensorChannel(
          id: "charge", label: "Charge", value: percentage,
          formattedValue: SensorFormatting.percentage(percentage), unit: "%", kind: .derived))
    }
    if let external {
      channels.append(
        SensorChannel(
          id: "power_source", label: "Power source", value: external ? 1 : 0,
          formattedValue: external ? "AC power" : "Battery"))
    }
    if let designCapacity, let nominalCapacity,
      let capacityRatio = BatteryMeasurements.capacityRatio(
        nominal: nominalCapacity, design: designCapacity)
    {
      channels.append(
        SensorChannel(
          id: "capacity_ratio", label: "Reported capacity ratio", value: capacityRatio,
          formattedValue: SensorFormatting.percentage(capacityRatio), unit: "%", kind: .derived,
          note:
            "Reported full-charge capacity ÷ design capacity; not Apple's Battery Health status."))
    }
    if let charging {
      channels.append(
        SensorChannel(
          id: "charging", label: "Charging", value: charging ? 1 : 0,
          formattedValue: charging ? "Yes" : "No"))
    }
    if let fullyCharged {
      channels.append(
        SensorChannel(
          id: "fully_charged", label: "Fully charged", value: fullyCharged ? 1 : 0,
          formattedValue: fullyCharged ? "Yes" : "No"))
    }
    if let cycles, cycles.isFinite, cycles >= 0 {
      channels.append(
        SensorChannel(
          id: "cycle_count", label: "Cycle count", value: cycles,
          formattedValue: SensorFormatting.decimal(cycles, fractionDigits: 0), unit: "cycles"))
    }
    if let designCapacity, designCapacity > 0 {
      channels.append(
        SensorChannel(
          id: "design_capacity", label: "Design capacity", value: designCapacity,
          formattedValue: SensorFormatting.decimal(designCapacity, fractionDigits: 0), unit: "mAh",
          note: "Fixed allowlisted AppleSmartBattery field."))
    }
    if let nominalCapacity, nominalCapacity >= 0 {
      channels.append(
        SensorChannel(
          id: "nominal_capacity", label: "Reported full-charge capacity",
          value: nominalCapacity,
          formattedValue: SensorFormatting.decimal(nominalCapacity, fractionDigits: 0), unit: "mAh",
          note: "Controller-reported capacity; it can change as the battery calibrates."))
    }
    if external == false, let timeRemaining {
      channels.append(
        SensorChannel(
          id: "time_remaining", label: "Estimated time remaining", value: timeRemaining,
          formattedValue: SensorFormatting.decimal(timeRemaining, fractionDigits: 0),
          unit: "minutes",
          kind: .estimated,
          note: "Controller estimate; unavailable sentinel values are omitted."))
    }
    if charging == true, let averageTimeToFull {
      channels.append(
        SensorChannel(
          id: "time_to_full", label: "Estimated time to full", value: averageTimeToFull,
          formattedValue: SensorFormatting.decimal(averageTimeToFull, fractionDigits: 0),
          unit: "minutes", kind: .estimated,
          note: "Controller estimate; unavailable sentinel values are omitted."))
    }
    if let voltage {
      channels.append(
        SensorChannel(
          id: "voltage", label: "Battery voltage", value: voltage,
          formattedValue: SensorFormatting.decimal(voltage, fractionDigits: 2), unit: "V",
          kind: .derived))
    }
    if let currentAmps {
      channels.append(
        SensorChannel(
          id: "current", label: "Battery current", value: currentAmps,
          formattedValue: SensorFormatting.decimal(currentAmps, fractionDigits: 2), unit: "A",
          kind: .derived))
    }
    if let power {
      channels.append(
        SensorChannel(
          id: "power", label: "Battery-side power", value: power,
          formattedValue: SensorFormatting.decimal(power, fractionDigits: 2), unit: "W",
          kind: .derived, note: "Voltage × current; not wall-plug power."))
    }
    if let temperature, (-20...100).contains(temperature) {
      channels.append(
        SensorChannel(
          id: "temperature", label: "Battery temperature", value: temperature,
          formattedValue: SensorFormatting.decimal(temperature, fractionDigits: 1), unit: "°C",
          kind: .derived, note: "Converted from the battery controller's raw deci-kelvin value."))
    }

    let powerSource = external.map { $0 ? "AC power" : "Battery" }
    let summary =
      switch (percentage, powerSource) {
      case (.some(let percentage), .some(let powerSource)):
        "\(SensorFormatting.percentage(percentage)) • \(powerSource)"
      case (.some(let percentage), .none):
        SensorFormatting.percentage(percentage)
      case (.none, .some(let powerSource)):
        powerSource
      case (.none, .none):
        "Battery telemetry available"
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
      notes: []
    )
  }
}
