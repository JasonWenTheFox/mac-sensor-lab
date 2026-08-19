import Foundation

public struct SMCSensorProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "thermal.smc",
    name: "SMC Sensors",
    category: .thermal,
    source: "AppleSMC read-only user client",
    capability: .undocumented
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    guard let smc = ReadOnlySMC() else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "AppleSMC is present but its user client could not be opened",
        status: .permissionRequired,
        source: metadata.source,
        capability: metadata.capability,
        notes: ["The App will not request sudo or attempt a privileged helper in this build."]
      )
    }

    let cpuSensors = [
      ("Tp00", "CPU super core 1"), ("Tp04", "CPU super core 2"),
      ("Tp08", "CPU super core 3"), ("Tp0C", "CPU super core 4"),
      ("Tp0G", "CPU super core 5"), ("Tp0K", "CPU super core 6"),
      ("Tp0O", "CPU performance core 1"), ("Tp0R", "CPU performance core 2"),
      ("Tp0U", "CPU performance core 3"), ("Tp0X", "CPU performance core 4"),
      ("Tp0a", "CPU performance core 5"), ("Tp0d", "CPU performance core 6"),
      ("Tp0g", "CPU performance core 7"), ("Tp0j", "CPU performance core 8"),
      ("Tp0m", "CPU performance core 9"), ("Tp0p", "CPU performance core 10"),
      ("Tp0u", "CPU performance core 11"), ("Tp0y", "CPU performance core 12"),
    ]
    let gpuSensors = [
      ("Tg0U", "GPU 1"), ("Tg0X", "GPU 2"), ("Tg0d", "GPU 3"),
      ("Tg0g", "GPU 4"), ("Tg0j", "GPU 5"), ("Tg1Y", "GPU 6"),
      ("Tg1c", "GPU 7"), ("Tg1g", "GPU 8"),
    ]
    let auxiliarySensors = [
      ("TaLP", "Airflow left"), ("TaRF", "Airflow right"),
      ("TH0x", "NAND"), ("TB1T", "Battery sensor 1"),
      ("TB2T", "Battery sensor 2"), ("TW0P", "Wi-Fi proximity"),
      ("Tm0p", "Memory proximity 1"), ("Tm1p", "Memory proximity 2"),
      ("Tm2p", "Memory proximity 3"),
    ]
    let cpuValues = validTemperatures(sensors: cpuSensors, smc: smc)
    let gpuValues = validTemperatures(sensors: gpuSensors, smc: smc)
    let auxiliaryValues = validTemperatures(sensors: auxiliarySensors, smc: smc)

    var channels: [SensorChannel] = []
    if let hotspot = cpuValues.map(\.value).max() {
      channels.append(
        temperatureChannel(id: "cpu_hotspot", label: "CPU hotspot", value: hotspot, kind: .derived))
    }
    if !cpuValues.isEmpty {
      let average = cpuValues.map(\.value).reduce(0, +) / Double(cpuValues.count)
      channels.append(
        temperatureChannel(id: "cpu_average", label: "CPU average", value: average, kind: .derived))
    }
    if let hotspot = gpuValues.map(\.value).max() {
      channels.append(
        temperatureChannel(id: "gpu_hotspot", label: "GPU hotspot", value: hotspot, kind: .derived))
    }
    if !gpuValues.isEmpty {
      let average = gpuValues.map(\.value).reduce(0, +) / Double(gpuValues.count)
      channels.append(
        temperatureChannel(id: "gpu_average", label: "GPU average", value: average, kind: .derived))
    }

    channels += cpuValues.map { rawTemperatureChannel(group: "cpu", sensor: $0) }
    channels += gpuValues.map { rawTemperatureChannel(group: "gpu", sensor: $0) }
    channels += auxiliaryValues.map { rawTemperatureChannel(group: "system", sensor: $0) }

    if let fanCount = smc.value(for: "FNum") {
      for index in 0..<min(Int(fanCount), 4) {
        if let rpm = smc.value(for: "F\(index)Ac"), (0...20_000).contains(rpm) {
          channels.append(
            SensorChannel(
              id: "fan_\(index)",
              label: "Fan \(index + 1)",
              value: rpm,
              formattedValue: SensorFormatting.decimal(rpm, fractionDigits: 0),
              unit: "RPM"
            ))
        }
      }
    }

    for item in [
      ("PSTR", "system_power", "System total power"),
      ("PDTR", "dc_input_power", "DC input power"),
      ("PPBR", "battery_power", "Battery power"),
      ("PMTR", "memory_power", "Memory total power"),
      ("PCTR", "cpu_power", "CPU total power"),
      ("PG0R", "gpu_power", "GPU power"),
      ("PBwo", "display_backlight_power", "Display backlight power"),
    ] {
      if let watts = smc.value(for: item.0), (-500...1_000).contains(watts) {
        channels.append(
          SensorChannel(
            id: item.1,
            label: item.2,
            value: watts,
            formattedValue: SensorFormatting.decimal(watts, fractionDigits: 2),
            unit: "W",
            note: "Internal SMC telemetry; not wall-plug power."
          ))
      }
    }

    guard !channels.isEmpty else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "SMC opened, but the current key allowlist returned no readings",
        status: .degraded,
        source: metadata.source,
        capability: metadata.capability,
        notes: ["The M5-oriented key allowlist may need model-specific updates."]
      )
    }

    let headline = channels.first(where: { $0.id == "cpu_hotspot" })
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: headline.map { "CPU hotspot \($0.formattedValue) °C" }
        ?? "\(channels.count) read-only channels",
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: [
        "Only a fixed M5-oriented allowlist of temperature, fan and power keys is read.",
        "No SMC write or fan-control method exists in this target.",
        "M5 key names are preliminary and require cross-model validation.",
      ]
    )
  }

  private func validTemperatures(
    sensors: [(key: String, label: String)], smc: ReadOnlySMC
  ) -> [(key: String, label: String, value: Double)] {
    sensors.compactMap { sensor in
      let key = sensor.key
      guard let value = smc.value(for: key), (0...110).contains(value) else { return nil }
      return (key, sensor.label, value)
    }
  }

  private func rawTemperatureChannel(
    group: String, sensor: (key: String, label: String, value: Double)
  ) -> SensorChannel {
    SensorChannel(
      id: "temperature_\(group)_\(sensor.key.lowercased())",
      label: sensor.label,
      value: sensor.value,
      formattedValue: SensorFormatting.decimal(sensor.value, fractionDigits: 1),
      unit: "°C",
      note: "Raw read-only SMC key \(sensor.key); model-specific meaning."
    )
  }

  private func temperatureChannel(
    id: String,
    label: String,
    value: Double,
    kind: SensorValueKind
  ) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: value,
      formattedValue: SensorFormatting.decimal(value, fractionDigits: 1),
      unit: "°C",
      kind: kind,
      note: "Internal component temperature, not ambient room temperature."
    )
  }
}
