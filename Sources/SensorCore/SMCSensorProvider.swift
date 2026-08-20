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

    return SMCSensorSnapshotBuilder(
      metadata: metadata,
      generation: AppleSiliconSMCGeneration.current()
    ).snapshot(valueFor: smc.value)
  }
}

struct SMCSensorSnapshotBuilder {
  let metadata: SensorProviderMetadata
  let generation: AppleSiliconSMCGeneration

  func snapshot(valueFor: (String) -> Double?) -> SensorSnapshot {
    let cpuValues = validTemperatures(
      sensors: SMCSensorCatalog.cpuSensors(for: generation),
      valueFor: valueFor
    )
    let gpuValues = validTemperatures(
      sensors: SMCSensorCatalog.gpuSensors(for: generation),
      valueFor: valueFor
    )
    let auxiliaryValues = validTemperatures(
      sensors: SMCSensorCatalog.auxiliarySensors(for: generation),
      valueFor: valueFor
    )

    var channels: [SensorChannel] = []
    if let hotspot = cpuValues.map(\.value).max() {
      channels.append(
        temperatureChannel(id: "cpu_hotspot", label: "CPU hotspot", value: hotspot, kind: .derived)
      )
    }
    if let average = finiteAverage(cpuValues.map(\.value)) {
      channels.append(
        temperatureChannel(id: "cpu_average", label: "CPU average", value: average, kind: .derived)
      )
    }
    if let hotspot = gpuValues.map(\.value).max() {
      channels.append(
        temperatureChannel(id: "gpu_hotspot", label: "GPU hotspot", value: hotspot, kind: .derived)
      )
    }
    if let average = finiteAverage(gpuValues.map(\.value)) {
      channels.append(
        temperatureChannel(id: "gpu_average", label: "GPU average", value: average, kind: .derived)
      )
    }

    channels += cpuValues.map { rawTemperatureChannel(group: "cpu", sensor: $0) }
    channels += gpuValues.map { rawTemperatureChannel(group: "gpu", sensor: $0) }
    channels += auxiliaryValues.map { rawTemperatureChannel(group: "system", sensor: $0) }

    if let fanCount = valueFor("FNum").flatMap({
      SensorNumericSafety.boundedNonnegativeInteger($0, maximum: 4)
    }) {
      for index in 0..<fanCount {
        if let rpm = valueFor("F\(index)Ac"), rpm.isFinite, (0...20_000).contains(rpm) {
          channels.append(
            SensorChannel(
              id: "fan_\(index)",
              label: "Fan \(index + 1)",
              value: rpm,
              formattedValue: SensorFormatting.decimal(rpm, fractionDigits: 0),
              unit: "RPM"
            )
          )
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
      if let watts = valueFor(item.0), watts.isFinite, (-500...1_000).contains(watts) {
        channels.append(
          SensorChannel(
            id: item.1,
            label: item.2,
            value: watts,
            formattedValue: SensorFormatting.decimal(watts, fractionDigits: 2),
            unit: "W",
            note: "Internal SMC telemetry; not wall-plug power."
          )
        )
      }
    }

    guard !channels.isEmpty else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: generation == .unknown
          ? "SMC opened, but common keys returned no readings"
          : "SMC opened, but the \(generation.displayName) key allowlist returned no readings",
        status: .degraded,
        source: metadata.source,
        capability: metadata.capability,
        notes: generationNotes
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
      notes: generationNotes
    )
  }

  private var generationNotes: [String] {
    let allowlistNote =
      generation == .unknown
      ? "CPU generation was not recognized; only fixed generation-neutral temperature, fan and power keys were read."
      : "Only a fixed \(generation.displayName) and generation-neutral allowlist of temperature, fan and power keys was read."
    return [
      allowlistNote,
      "CPU generation selects an allowlist only; the brand string is not retained or exported.",
      "No SMC write or fan-control method exists in this target.",
      "Undocumented key meanings require anonymous cross-model validation.",
    ]
  }

  private func validTemperatures(
    sensors: [SMCTemperatureSensorDefinition],
    valueFor: (String) -> Double?
  ) -> [(key: String, label: String, value: Double)] {
    sensors.compactMap { sensor in
      guard let value = valueFor(sensor.key), value.isFinite, (0...110).contains(value) else {
        return nil
      }
      return (sensor.key, sensor.label, value)
    }
  }

  private func finiteAverage(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    var total = 0.0
    for value in values {
      let sum = total + value
      guard sum.isFinite else { return nil }
      total = sum
    }
    let average = total / Double(values.count)
    return average.isFinite ? average : nil
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
