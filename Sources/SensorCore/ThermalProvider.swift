import Foundation

public enum SystemThermalPressure: Int, CaseIterable, Equatable, Sendable {
  case nominal = 0
  case fair = 1
  case serious = 2
  case critical = 3

  init?(systemState: ProcessInfo.ThermalState) {
    switch systemState {
    case .nominal: self = .nominal
    case .fair: self = .fair
    case .serious: self = .serious
    case .critical: self = .critical
    @unknown default: return nil
    }
  }

  public var displayName: String {
    switch self {
    case .nominal: "Nominal"
    case .fair: "Fair"
    case .serious: "Serious"
    case .critical: "Critical"
    }
  }
}

struct PublicThermalReading: Equatable, Sendable {
  let pressure: SystemThermalPressure?
  let lowPowerModeEnabled: Bool
}

public struct ThermalProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "thermal.pressure",
    name: "Thermals",
    category: .thermal,
    source: "Foundation ProcessInfo",
    capability: .publicAPI
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let info = ProcessInfo.processInfo
    return snapshot(
      reading: PublicThermalReading(
        pressure: SystemThermalPressure(systemState: info.thermalState),
        lowPowerModeEnabled: info.isLowPowerModeEnabled
      )
    )
  }

  func snapshot(reading: PublicThermalReading) -> SensorSnapshot {
    var channels: [SensorChannel] = []
    if let pressure = reading.pressure {
      channels += [
        SensorChannel(
          id: "thermal_state",
          label: "Thermal pressure",
          formattedValue: pressure.displayName
        ),
        SensorChannel(
          id: "thermal_pressure_level",
          label: "Thermal pressure level",
          value: Double(pressure.rawValue),
          formattedValue: pressure.displayName,
          kind: .derived,
          note:
            "Ordinal encoding for trend display only; level spacing is not physical and no temperature is inferred."
        ),
      ]
    }
    channels.append(
      SensorChannel(
        id: "low_power_mode",
        label: "Low Power Mode",
        value: reading.lowPowerModeEnabled ? 1 : 0,
        formattedValue: reading.lowPowerModeEnabled ? "On" : "Off"
      )
    )

    let state = reading.pressure?.displayName.lowercased() ?? "unknown"
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "Thermal pressure \(state)",
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: ["Thermal pressure is a public system state, not a temperature in degrees."]
    )
  }
}
