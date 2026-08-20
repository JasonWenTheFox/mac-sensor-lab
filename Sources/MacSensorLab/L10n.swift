import Foundation

/// Centralized UI localization for the native app target.
///
/// Sensor payloads remain stable English facts for export and diagnostics. The app resolves their
/// display strings here when a matching translation exists, so localization never changes IDs or
/// serialized data.
public enum L10n {
  public static func text(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
  }

  public static func format(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: text(key), locale: .current, arguments: arguments)
  }

  /// Localizes a sensor-owned display string without changing the underlying snapshot.
  ///
  /// Providers intentionally emit stable English facts for export and diagnostics. This method
  /// recognizes only the app's bounded display templates, so arbitrary driver or system error
  /// text is never parsed or rewritten.
  public static func sensorText(_ value: String) -> String {
    SensorTextLocalizer(localize: text, locale: .current).localized(value)
  }
}

struct SensorTextLocalizer {
  let localize: (String) -> String
  let locale: Locale

  func localized(_ value: String) -> String {
    let exact = localize(value)
    if exact != value { return exact }

    if let minutes = integer(between: "Load average (", and: " min)", in: value) {
      return formatted("Load average (%lld min)", minutes)
    }
    if let fan = integer(after: "Fan ", in: value) {
      return formatted("Fan %lld", fan)
    }
    if let channel = integer(after: "Spectral channel ", in: value) {
      return formatted("Spectral channel %lld", channel)
    }
    for prefix in ["Acceleration", "Angular velocity"] {
      for axis in ["X", "Y", "Z"] where value == "\(prefix) \(axis)" {
        return formatted("%@ %@", localized(prefix), axis)
      }
    }

    if let (architecture, memory) = pair(in: value, separator: " • "),
      memory.hasSuffix(" memory")
    {
      return formatted(
        "%@ • %@ memory",
        architecture,
        String(memory.dropLast(" memory".count))
      )
    }
    if let activeCount = integer(afterLast: " • ", before: " active", in: value) {
      let resolution = String(value.prefix(value.count - " • \(activeCount) active".count))
      return formatted("%@ • %lld active", resolution, activeCount)
    }
    if let activeCount = integer(before: " active displays", in: value) {
      return formatted("%lld active displays", activeCount)
    }
    if value.hasPrefix("CPU hotspot "), value.hasSuffix(" °C") {
      let reading = String(value.dropFirst("CPU hotspot ".count).dropLast(" °C".count))
      return formatted("CPU hotspot %@ °C", reading)
    }
    if value.hasPrefix("CPU ") {
      return formatted("CPU %@", String(value.dropFirst("CPU ".count)))
    }
    if value.hasPrefix("GPU ") {
      return formatted("GPU %@", String(value.dropFirst("GPU ".count)))
    }
    if value.hasPrefix("Thermal pressure ") {
      let state = String(value.dropFirst("Thermal pressure ".count)).capitalized
      return formatted("Thermal pressure %@", localized(state))
    }
    if let count = integer(
      between: "Collecting network baseline • ", and: " active interfaces", in: value)
    {
      return formatted("Collecting network baseline • %lld active interfaces", count)
    }
    if let count = integer(
      between: "Collecting activity baseline • ", and: " block devices", in: value)
    {
      return formatted("Collecting activity baseline • %lld block devices", count)
    }
    if value.hasPrefix("Collecting CPU baseline • load ") {
      return formatted(
        "Collecting CPU baseline • load %@",
        String(value.dropFirst("Collecting CPU baseline • load ".count))
      )
    }
    if let (read, write) = pair(in: value, separator: " • Write "), read.hasPrefix("Read ") {
      return formatted("Read %@ • Write %@", String(read.dropFirst("Read ".count)), write)
    }
    if let (measurement, powerSource) = pair(in: value, separator: " • "),
      powerSource == "Battery" || powerSource == "AC power"
    {
      return formatted("%@ • %@", measurement, localized(powerSource))
    }
    if let count = twoIntegers(
      between: "", middle: " of ", and: " capabilities detected", in: value)
    {
      return formatted("%lld of %lld capabilities detected", count.0, count.1)
    }
    if let count = integer(before: " experimental sensor types detected", in: value) {
      return formatted("%lld experimental sensor types detected", count)
    }
    if let count = integer(before: " read-only channels", in: value) {
      return formatted("%lld read-only channels", count)
    }
    if value.hasPrefix("SMC opened, but the "),
      value.hasSuffix(" key allowlist returned no readings")
    {
      let generation = String(
        value.dropFirst("SMC opened, but the ".count)
          .dropLast(" key allowlist returned no readings".count)
      )
      return formatted("SMC opened, but the %@ key allowlist returned no readings", generation)
    }
    if value.hasPrefix("Live "), value.hasSuffix(" data") {
      let groups = String(value.dropFirst("Live ".count).dropLast(" data".count))
        .components(separatedBy: ", ")
        .map { localized(String($0)) }
        .joined(separator: localize(", "))
      return formatted("Live %@ data", groups)
    }
    if value.hasSuffix(" available") {
      let measurement = String(value.dropLast(" available".count))
      if measurement.first?.isNumber == true {
        return formatted("%@ available", measurement)
      }
    }
    if value.hasPrefix("Showing the last successful sample from "),
      value.hasSuffix(" seconds ago; its original timestamp is preserved.")
    {
      let age = String(
        value.dropFirst("Showing the last successful sample from ".count)
          .dropLast(" seconds ago; its original timestamp is preserved.".count)
      )
      return formatted(
        "Showing the last successful sample from %@ seconds ago; its original timestamp is preserved.",
        age
      )
    }
    if value.hasPrefix("Raw read-only SMC key "),
      value.hasSuffix("; model-specific meaning.")
    {
      let key = String(
        value.dropFirst("Raw read-only SMC key ".count)
          .dropLast("; model-specific meaning.".count)
      )
      return formatted("Raw read-only SMC key %@; model-specific meaning.", key)
    }
    if value.hasPrefix("Only a fixed "),
      value.hasSuffix(
        " and generation-neutral allowlist of temperature, fan and power keys was read."
      )
    {
      let generation = String(
        value.dropFirst("Only a fixed ".count)
          .dropLast(
            " and generation-neutral allowlist of temperature, fan and power keys was read."
              .count)
      )
      return formatted(
        "Only a fixed %@ and generation-neutral allowlist of temperature, fan and power keys was read.",
        generation
      )
    }
    if value.hasPrefix("HID open result: "), value.hasSuffix(".") {
      let result = String(value.dropFirst("HID open result: ".count).dropLast())
      return formatted("HID open result: %@.", result)
    }

    return exact
  }

  private func formatted(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: localize(key), locale: locale, arguments: arguments)
  }

  private func integer(after prefix: String, in value: String) -> Int64? {
    guard value.hasPrefix(prefix) else { return nil }
    return Int64(value.dropFirst(prefix.count))
  }

  private func integer(before suffix: String, in value: String) -> Int64? {
    guard value.hasSuffix(suffix) else { return nil }
    return Int64(value.dropLast(suffix.count))
  }

  private func integer(between prefix: String, and suffix: String, in value: String) -> Int64? {
    guard value.hasPrefix(prefix), value.hasSuffix(suffix) else { return nil }
    return Int64(value.dropFirst(prefix.count).dropLast(suffix.count))
  }

  private func integer(afterLast separator: String, before suffix: String, in value: String)
    -> Int64?
  {
    guard value.hasSuffix(suffix), let range = value.range(of: separator, options: .backwards)
    else { return nil }
    return Int64(value[range.upperBound..<value.index(value.endIndex, offsetBy: -suffix.count)])
  }

  private func pair(in value: String, separator: String) -> (String, String)? {
    guard let range = value.range(of: separator) else { return nil }
    return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
  }

  private func twoIntegers(
    between prefix: String,
    middle: String,
    and suffix: String,
    in value: String
  ) -> (Int64, Int64)? {
    guard value.hasPrefix(prefix), value.hasSuffix(suffix) else { return nil }
    let body = value.dropFirst(prefix.count).dropLast(suffix.count)
    guard let range = body.range(of: middle),
      let first = Int64(body[..<range.lowerBound]),
      let second = Int64(body[range.upperBound...])
    else { return nil }
    return (first, second)
  }
}
