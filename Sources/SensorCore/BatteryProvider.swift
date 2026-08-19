import Foundation
import IOKit

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

    let current = IOKitHelpers.number(service, key: "CurrentCapacity")
    let maximum = IOKitHelpers.number(service, key: "MaxCapacity")
    let external = IOKitHelpers.bool(service, key: "ExternalConnected") ?? false
    let charging = IOKitHelpers.bool(service, key: "IsCharging") ?? false
    let fullyCharged = IOKitHelpers.bool(service, key: "FullyCharged") ?? false
    let cycles = IOKitHelpers.number(service, key: "CycleCount")
    let voltageMillivolts = IOKitHelpers.number(service, key: "Voltage")
    let amperageMilliamps = IOKitHelpers.number(service, key: "Amperage")
    let temperatureRaw = IOKitHelpers.number(service, key: "Temperature")

    let percentage: Double? =
      if let current, let maximum, maximum > 0 {
        current / maximum * 100
      } else {
        nil
      }
    let voltage = voltageMillivolts.map { $0 / 1000 }
    let currentAmps = amperageMilliamps.map { $0 / 1000 }
    let power: Double? = if let voltage, let currentAmps { voltage * currentAmps } else { nil }
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
    channels.append(
      SensorChannel(
        id: "power_source", label: "Power source", value: external ? 1 : 0,
        formattedValue: external ? "AC power" : "Battery"))
    channels.append(
      SensorChannel(
        id: "charging", label: "Charging", value: charging ? 1 : 0,
        formattedValue: charging ? "Yes" : "No"))
    channels.append(
      SensorChannel(
        id: "fully_charged", label: "Fully charged", value: fullyCharged ? 1 : 0,
        formattedValue: fullyCharged ? "Yes" : "No"))
    if let cycles {
      channels.append(
        SensorChannel(
          id: "cycle_count", label: "Cycle count", value: cycles,
          formattedValue: SensorFormatting.decimal(cycles, fractionDigits: 0), unit: "cycles"))
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

    let summary =
      percentage.map { "\(SensorFormatting.percentage($0)) • \(external ? "AC power" : "Battery")" }
      ?? (external ? "AC power" : "Battery")
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
        "Only a fixed allowlist of non-identifying registry keys is read.",
        "Battery-side power is not whole-system wall power.",
      ]
    )
  }
}
