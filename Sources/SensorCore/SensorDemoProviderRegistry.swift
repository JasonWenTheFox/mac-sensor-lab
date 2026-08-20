import Foundation

/// Deterministic, identity-free fixtures for screenshots, UI review, and hardware-free demos.
/// Demo mode is opt-in and every snapshot source is explicitly labeled as fixture data.
public enum SensorDemoProviderRegistry {
  public static func providers() -> [any SensorProvider] {
    [
      provider(
        "system.overview", "System", .system, .publicAPI,
        "Apple Silicon (demo) • 32 GB memory",
        [
          text("architecture", "Architecture", "Apple Silicon (demo)"),
          number("logical_processors", "Logical processors", 10),
          number("active_processors", "Active processors", 10),
          bytes("physical_memory", "Physical memory", 32 * gibibyte),
          text("os_version", "macOS", "Demo fixture"),
          number("uptime", "System uptime", 42.5, "hours"),
        ]),
      provider(
        "system.performance", "Performance", .system, .publicAPI, "CPU 38%",
        [
          percent("cpu_utilization", "CPU utilization", 38, .derived),
          number("load_average_1m", "Load average (1 min)", 2.14),
          number("load_average_5m", "Load average (5 min)", 1.92),
          number("load_average_15m", "Load average (15 min)", 1.61),
          bytes("memory_free", "Free memory", 5 * gibibyte),
          bytes("memory_active", "Active memory", 13 * gibibyte),
          bytes("memory_inactive", "Inactive memory", 6 * gibibyte),
          bytes("memory_wired", "Wired memory", 5 * gibibyte),
          bytes("memory_compressed", "Compressed memory", 2 * gibibyte),
          bytes("swap_used", "Swap used", 768 * mebibyte),
          bytes("swap_total", "Swap total", 4 * gibibyte),
        ]),
      provider(
        "system.gpu_performance", "GPU Performance", .system, .undocumented, "GPU 27%",
        [
          number("gpu_driver_count", "GPU driver instances", 1),
          percent("gpu_device_utilization", "GPU device utilization", 27),
          percent("gpu_renderer_utilization", "Renderer utilization", 25),
          percent("gpu_tiler_utilization", "Tiler utilization", 18),
          bytes("gpu_memory_in_use", "GPU memory in use", 3 * gibibyte),
          bytes("gpu_memory_allocated", "GPU memory allocated", 4 * gibibyte),
        ]),
      provider(
        "system.network_throughput", "Network Throughput", .system, .publicAPI,
        "↓ 1.25 MB/s • ↑ 320 KB/s",
        [
          number("network_active_interfaces", "Active non-loopback interfaces", 3),
          bytes("network_received_total", "Received total", 24 * gibibyte),
          bytes("network_sent_total", "Sent total", 8 * gibibyte),
          rate("network_receive_rate", "Receive rate", 1.25 * mebibyte),
          rate("network_send_rate", "Send rate", 320 * kibibyte),
        ]),
      provider(
        "power.source", "System Power Source", .power, .publicAPI, "78% • Battery",
        [
          text("active_source", "Active power source", "Battery"),
          percent("battery_charge", "Battery charge (public API)", 78, .derived),
          text("battery_charging", "Battery charging (public API)", "No", 0),
          text("battery_warning", "System low-battery warning", "No warning"),
          number(
            "system_time_remaining", "System time remaining", 285, "minutes", .estimated),
          number(
            "battery_time_to_empty", "Battery time to empty (public API)", 285, "minutes",
            .estimated),
        ]),
      provider(
        "power.battery", "Power & Battery", .power, .undocumented, "78% • Battery",
        [
          percent("charge", "Charge", 78, .derived),
          text("power_source", "Power source", "Battery", 0),
          percent("capacity_ratio", "Reported capacity ratio", 96, .derived),
          text("charging", "Charging", "No", 0),
          number("cycle_count", "Cycle count", 84, "cycles"),
          number("time_remaining", "Estimated time remaining", 285, "minutes", .estimated),
          number("voltage", "Battery voltage", 12.4, "V", .derived),
          number("current", "Battery current", -1.1, "A", .derived),
          number("power", "Battery-side power", -13.6, "W", .derived),
          number("temperature", "Battery temperature", 31.8, "°C", .derived),
        ]),
      provider(
        "thermal.pressure", "Thermals", .thermal, .publicAPI,
        "Thermal pressure nominal",
        [
          text("thermal_state", "Thermal pressure", "Nominal"),
          text("low_power_mode", "Low Power Mode", "Off", 0),
        ]),
      provider(
        "thermal.smc", "SMC Sensors", .thermal, .undocumented, "CPU hotspot 54.2 °C",
        [
          number("cpu_hotspot", "CPU hotspot", 54.2, "°C", .derived),
          number("cpu_average", "CPU average", 49.7, "°C", .derived),
          number("gpu_hotspot", "GPU hotspot", 47.6, "°C", .derived),
          number("fan_0", "Fan 1", 1_840, "RPM"),
          number("system_power", "System total power", 24.8, "W"),
          number("cpu_power", "CPU total power", 8.6, "W"),
          number("gpu_power", "GPU power", 4.1, "W"),
        ]),
      provider(
        "display.active", "Display", .display, .publicAPI, "3024 × 1964 px • 1 active",
        [
          number("display_count", "Active displays", 1),
          text("main_resolution", "Main display pixels", "3024 × 1964", nil, "pixels"),
          text(
            "main_logical_resolution", "Main display logical size", "1512 × 982", nil, "points"
          ),
          number("backing_scale", "Backing scale", 2, "×", .derived),
          number("refresh_rate", "Refresh rate", 120, "Hz"),
        ]),
      provider(
        "storage.system_volume", "Storage", .storage, .publicAPI, "438 GB available",
        [
          bytes("total", "Capacity", 1_000_000_000_000),
          bytes("available", "Available", 438_000_000_000),
          bytes("available_important", "Available for important usage", 500_000_000_000),
          bytes("available_opportunistic", "Available for opportunistic usage", 300_000_000_000),
          bytes("used", "Used", 562_000_000_000),
          percent("used_percent", "Used", 56.2, .derived),
        ]),
      provider(
        "storage.disk_io", "Disk Activity", .storage, .publicAPI,
        "Read 18 MB/s • write 4 MB/s",
        [
          number("disk_device_count", "Aggregated block devices", 1),
          rate("disk_read_rate", "Read rate", 18 * mebibyte),
          rate("disk_write_rate", "Write rate", 4 * mebibyte),
          number("disk_read_operation_rate", "Read operation rate", 420, "ops/s", .derived),
          number("disk_write_operation_rate", "Write operation rate", 95, "ops/s", .derived),
        ]),
      provider(
        "motion.spu_discovery", "Apple SPU Discovery", .motion, .undocumented,
        "3 experimental sensor types detected",
        [
          text("accelerometer", "Accelerometer", "Detected", 1),
          text("gyroscope", "Gyroscope", "Detected", 1),
          text("ambient_light", "Ambient light", "Detected", 1),
        ]),
      provider(
        "motion.spu_live", "Motion & Ambient Light", .motion, .undocumented,
        "Live acceleration, level, ambient data",
        [
          number("acceleration_x", "Acceleration X", 0.02, "g"),
          number("acceleration_y", "Acceleration Y", -0.01, "g"),
          number("acceleration_z", "Acceleration Z", 0.998, "g"),
          number("acceleration_magnitude", "Acceleration magnitude", 0.998, "g", .derived),
          number("level_roll", "Estimated roll", 1.2, "°", .estimated),
          number("level_pitch", "Estimated pitch", -0.7, "°", .estimated),
          number("ambient_intensity", "Ambient intensity", 24.6, "raw"),
          number("ambient_spectral_1", "Spectral channel 1", 18.2, "raw"),
          number("ambient_spectral_2", "Spectral channel 2", 22.7, "raw"),
          number("ambient_spectral_3", "Spectral channel 3", 25.1, "raw"),
          number("ambient_spectral_4", "Spectral channel 4", 20.4, "raw"),
        ]),
      provider(
        "motion.lid_angle", "Lid Angle", .motion, .undocumented, "104.5°",
        [number("angle", "Opening angle", 104.5, "°")]),
      provider(
        "diagnostics.hardware_capabilities", "Experimental Hardware", .diagnostics,
        .undocumented, "3 of 3 capabilities detected",
        [
          text("apple_spu", "Apple SPU", "Detected", 1),
          text("apple_smc", "Apple SMC", "Detected", 1),
          text("force_touch", "Force Touch trackpad", "Detected", 1),
        ]),
    ]
  }

  private static let kibibyte = 1_024.0
  private static let mebibyte = 1_024.0 * kibibyte
  private static let gibibyte = 1_024.0 * mebibyte

  private static func provider(
    _ id: String, _ name: String, _ category: SensorCategory,
    _ capability: SensorCapability, _ summary: String, _ channels: [SensorChannel]
  ) -> any SensorProvider {
    DemoSensorProvider(
      metadata: SensorProviderMetadata(
        id: id, name: name, category: category,
        source: "Built-in deterministic demo fixture", capability: capability),
      summary: summary,
      channels: channels)
  }

  private static func text(
    _ id: String, _ label: String, _ formattedValue: String, _ value: Double? = nil,
    _ unit: String? = nil, _ kind: SensorValueKind = .raw
  ) -> SensorChannel {
    SensorChannel(
      id: id, label: label, value: value, formattedValue: formattedValue, unit: unit, kind: kind
    )
  }

  private static func number(
    _ id: String, _ label: String, _ value: Double, _ unit: String? = nil,
    _ kind: SensorValueKind = .raw
  ) -> SensorChannel {
    SensorChannel(
      id: id, label: label, value: value,
      formattedValue: SensorFormatting.decimal(value, fractionDigits: 2),
      unit: unit, kind: kind)
  }

  private static func percent(
    _ id: String, _ label: String, _ value: Double, _ kind: SensorValueKind = .raw
  ) -> SensorChannel {
    SensorChannel(
      id: id, label: label, value: value,
      formattedValue: SensorFormatting.percentage(value), unit: "%", kind: kind)
  }

  private static func bytes(_ id: String, _ label: String, _ value: Double) -> SensorChannel {
    SensorChannel(
      id: id, label: label, value: value,
      formattedValue: SensorFormatting.bytes(UInt64(value)), unit: "bytes")
  }

  private static func rate(_ id: String, _ label: String, _ value: Double) -> SensorChannel {
    SensorChannel(
      id: id, label: label, value: value,
      formattedValue: SensorFormatting.bytesPerSecond(value), unit: "bytes/s", kind: .derived)
  }
}

private struct DemoSensorProvider: SensorProvider {
  let metadata: SensorProviderMetadata
  let summary: String
  let channels: [SensorChannel]

  func read() async -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id, name: metadata.name, category: metadata.category,
      summary: summary, status: .available, source: metadata.source,
      capability: metadata.capability, channels: channels,
      notes: ["Synthetic demo data; not a hardware reading."], timestamp: .now)
  }
}
