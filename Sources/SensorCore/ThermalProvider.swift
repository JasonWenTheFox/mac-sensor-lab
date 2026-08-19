import Foundation

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
    let state: String =
      switch info.thermalState {
      case .nominal: "Nominal"
      case .fair: "Fair"
      case .serious: "Serious"
      case .critical: "Critical"
      @unknown default: "Unknown"
      }
    let lowPower = info.isLowPowerModeEnabled

    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "Thermal pressure \(state.lowercased())",
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: [
        SensorChannel(id: "thermal_state", label: "Thermal pressure", formattedValue: state),
        SensorChannel(
          id: "low_power_mode", label: "Low Power Mode", value: lowPower ? 1 : 0,
          formattedValue: lowPower ? "On" : "Off"),
      ],
      notes: ["Thermal pressure is a public system state, not a temperature in degrees."]
    )
  }
}
