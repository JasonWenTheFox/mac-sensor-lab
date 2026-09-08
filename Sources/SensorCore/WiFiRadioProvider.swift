@preconcurrency import CoreWLAN
import Foundation

enum WiFiRadioBand: Equatable, Sendable {
  case band2GHz
  case band5GHz
  case band6GHz

  init?(coreWLANRawValue: Int) {
    switch coreWLANRawValue {
    case 1: self = .band2GHz
    case 2: self = .band5GHz
    case 3: self = .band6GHz
    default: return nil
    }
  }

  var displayName: String {
    switch self {
    case .band2GHz: "2.4 GHz"
    case .band5GHz: "5 GHz"
    case .band6GHz: "6 GHz"
    }
  }
}

enum WiFiChannelWidth: Int, Equatable, Sendable {
  case mhz20 = 20
  case mhz40 = 40
  case mhz80 = 80
  case mhz160 = 160

  init?(coreWLANRawValue: Int) {
    switch coreWLANRawValue {
    case 1: self = .mhz20
    case 2: self = .mhz40
    case 3: self = .mhz80
    case 4: self = .mhz160
    default: return nil
    }
  }
}

enum WiFiPHYMode: Equatable, Sendable {
  case mode11a
  case mode11b
  case mode11g
  case mode11n
  case mode11ac
  case mode11ax
  case mode11be

  init?(coreWLANRawValue: Int) {
    switch coreWLANRawValue {
    case 1: self = .mode11a
    case 2: self = .mode11b
    case 3: self = .mode11g
    case 4: self = .mode11n
    case 5: self = .mode11ac
    case 6: self = .mode11ax
    case 7: self = .mode11be
    default: return nil
    }
  }

  var displayName: String {
    switch self {
    case .mode11a: "802.11a"
    case .mode11b: "802.11b"
    case .mode11g: "802.11g"
    case .mode11n: "802.11n"
    case .mode11ac: "802.11ac"
    case .mode11ax: "802.11ax"
    case .mode11be: "802.11be"
    }
  }
}

enum WiFiSecurityMode: Equatable, Sendable {
  case open
  case wep
  case wpaPersonal
  case wpaPersonalMixed
  case wpa2Personal
  case personal
  case dynamicWEP
  case wpaEnterprise
  case wpaEnterpriseMixed
  case wpa2Enterprise
  case enterprise
  case wpa3Personal
  case wpa3Enterprise
  case wpa3Transition
  case owe
  case oweTransition

  init?(coreWLANRawValue: Int) {
    switch coreWLANRawValue {
    case 0: self = .open
    case 1: self = .wep
    case 2: self = .wpaPersonal
    case 3: self = .wpaPersonalMixed
    case 4: self = .wpa2Personal
    case 5: self = .personal
    case 6: self = .dynamicWEP
    case 7: self = .wpaEnterprise
    case 8: self = .wpaEnterpriseMixed
    case 9: self = .wpa2Enterprise
    case 10: self = .enterprise
    case 11: self = .wpa3Personal
    case 12: self = .wpa3Enterprise
    case 13: self = .wpa3Transition
    case 14: self = .owe
    case 15: self = .oweTransition
    default: return nil
    }
  }

  var displayName: String {
    switch self {
    case .open: "Open network"
    case .wep: "WEP"
    case .wpaPersonal: "WPA Personal"
    case .wpaPersonalMixed: "WPA/WPA2 Personal"
    case .wpa2Personal: "WPA2 Personal"
    case .personal: "Personal security"
    case .dynamicWEP: "Dynamic WEP"
    case .wpaEnterprise: "WPA Enterprise"
    case .wpaEnterpriseMixed: "WPA/WPA2 Enterprise"
    case .wpa2Enterprise: "WPA2 Enterprise"
    case .enterprise: "Enterprise security"
    case .wpa3Personal: "WPA3 Personal"
    case .wpa3Enterprise: "WPA3 Enterprise"
    case .wpa3Transition: "WPA3 transition"
    case .owe: "OWE"
    case .oweTransition: "OWE transition"
    }
  }
}

struct WiFiRadioChannelReading: Equatable, Sendable {
  let number: Int
  let widthRawValue: Int
  let bandRawValue: Int
}

struct WiFiRadioReading: Equatable, Sendable {
  let powerOn: Bool
  let serviceActive: Bool
  let channel: WiFiRadioChannelReading?
  let rssiDBm: Int
  let noiseDBm: Int
  let transmitRateMbps: Double
  let transmitPowerMW: Int
  let phyModeRawValue: Int
  let securityRawValue: Int
}

enum WiFiRadioMeasurements {
  static func rssi(_ value: Int) -> Double? {
    (-120 ... -1).contains(value) ? Double(value) : nil
  }

  static func noise(_ value: Int) -> Double? {
    (-140 ... -1).contains(value) ? Double(value) : nil
  }

  static func signalToNoise(rssi: Double?, noise: Double?) -> Double? {
    guard let rssi, let noise else { return nil }
    let result = rssi - noise
    guard result.isFinite, (-140...140).contains(result) else { return nil }
    return result
  }

  static func channelNumber(_ value: Int) -> Double? {
    (1...1_000).contains(value) ? Double(value) : nil
  }

  static func transmitRate(_ value: Double) -> Double? {
    guard value.isFinite, (0.01...100_000).contains(value) else { return nil }
    return value
  }

  static func transmitPower(_ value: Int) -> Double? {
    (1...10_000).contains(value) ? Double(value) : nil
  }
}

public struct WiFiRadioProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "connectivity.wifi_radio",
    name: "Wi-Fi Radio",
    category: .system,
    source: "CoreWLAN",
    capability: .publicAPI
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let client = CWWiFiClient.shared()
    guard let interface = client.interface() else {
      return snapshot(reading: nil)
    }

    let channel = interface.wlanChannel().map {
      WiFiRadioChannelReading(
        number: $0.channelNumber,
        widthRawValue: $0.channelWidth.rawValue,
        bandRawValue: $0.channelBand.rawValue
      )
    }
    return snapshot(
      reading: WiFiRadioReading(
        powerOn: interface.powerOn(),
        serviceActive: interface.serviceActive(),
        channel: channel,
        rssiDBm: interface.rssiValue(),
        noiseDBm: interface.noiseMeasurement(),
        transmitRateMbps: interface.transmitRate(),
        transmitPowerMW: interface.transmitPower(),
        phyModeRawValue: interface.activePHYMode().rawValue,
        securityRawValue: interface.security().rawValue
      )
    )
  }

  func snapshot(reading: WiFiRadioReading?) -> SensorSnapshot {
    guard let reading else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Wi-Fi interface was not reported",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability,
        readiness: readiness(
          presence: .unknown,
          readPath: .unavailable,
          stream: .inactive,
          feature: .unknown
        ),
        notes: privacyNotes
      )
    }

    var channels = [
      stateChannel(
        id: "wifi_power_on", label: "Wi-Fi power", enabled: reading.powerOn,
        enabledText: "On", disabledText: "Off"),
      stateChannel(
        id: "wifi_service_active", label: "Wi-Fi network service",
        enabled: reading.serviceActive, enabledText: "Active", disabledText: "Inactive"),
      stateChannel(
        id: "wifi_associated", label: "Associated radio link",
        enabled: reading.channel != nil, enabledText: "Associated", disabledText: "Not associated",
        kind: .derived),
    ]

    guard reading.powerOn else {
      return stateSnapshot(
        summary: "Wi-Fi power is off or unavailable",
        channels: channels,
        feature: .partial
      )
    }
    guard reading.serviceActive else {
      return stateSnapshot(
        summary: "Wi-Fi service is inactive or unavailable",
        channels: channels,
        feature: .partial
      )
    }
    guard let channel = reading.channel else {
      return stateSnapshot(
        summary: "No associated Wi-Fi channel was reported",
        channels: channels,
        feature: .partial
      )
    }

    let rssi = WiFiRadioMeasurements.rssi(reading.rssiDBm)
    let noise = WiFiRadioMeasurements.noise(reading.noiseDBm)
    let snr = WiFiRadioMeasurements.signalToNoise(rssi: rssi, noise: noise)
    if let rssi {
      channels.append(numericChannel("wifi_rssi", "RSSI", rssi, "dBm"))
    }
    if let noise {
      channels.append(numericChannel("wifi_noise", "Noise", noise, "dBm"))
    }
    if let snr {
      channels.append(
        numericChannel("wifi_snr", "Signal-to-noise ratio", snr, "dB", kind: .derived)
      )
    }
    if let number = WiFiRadioMeasurements.channelNumber(channel.number) {
      channels.append(numericChannel("wifi_channel", "Channel", number, nil))
    }
    if let width = WiFiChannelWidth(coreWLANRawValue: channel.widthRawValue) {
      channels.append(
        numericChannel("wifi_channel_width", "Channel width", Double(width.rawValue), "MHz")
      )
    }
    if let band = WiFiRadioBand(coreWLANRawValue: channel.bandRawValue) {
      channels.append(textChannel("wifi_band", "Band", band.displayName))
    }
    if let phy = WiFiPHYMode(coreWLANRawValue: reading.phyModeRawValue) {
      channels.append(textChannel("wifi_phy_mode", "PHY mode", phy.displayName))
    }
    if let rate = WiFiRadioMeasurements.transmitRate(reading.transmitRateMbps) {
      channels.append(numericChannel("wifi_transmit_rate", "Transmit rate", rate, "Mbps"))
    }
    if let power = WiFiRadioMeasurements.transmitPower(reading.transmitPowerMW) {
      channels.append(numericChannel("wifi_transmit_power", "Transmit power", power, "mW"))
    }
    if let security = WiFiSecurityMode(coreWLANRawValue: reading.securityRawValue) {
      channels.append(textChannel("wifi_security", "Security", security.displayName))
    }

    let status: SensorStatus = rssi == nil ? .degraded : .available
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: rssi == nil
        ? "Associated Wi-Fi signal unavailable" : "Wi-Fi radio metrics available",
      status: status,
      source: metadata.source,
      capability: metadata.capability,
      readiness: readiness(
        presence: .present,
        readPath: status == .available ? .ready : .limited,
        stream: status == .available ? .active : .inactive,
        feature: status == .available ? .ready : .partial
      ),
      channels: channels,
      notes: privacyNotes
    )
  }

  private var privacyNotes: [String] {
    [
      "No SSID, BSSID, MAC address, country code, interface name, scan result, IP address, or location was read.",
      "Transmit rate is the current negotiated PHY rate, not application throughput.",
      "Zero-valued CoreWLAN error sentinels and unknown enum values are omitted.",
    ]
  }

  private func stateSnapshot(
    summary: String,
    channels: [SensorChannel],
    feature: SensorFeatureReadiness
  ) -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: .degraded,
      source: metadata.source,
      capability: metadata.capability,
      readiness: readiness(
        presence: .present,
        readPath: .ready,
        stream: .inactive,
        feature: feature
      ),
      channels: channels,
      notes: privacyNotes
    )
  }

  private func readiness(
    presence: SensorHardwarePresence,
    readPath: SensorReadPathReadiness,
    stream: SensorStreamReadiness,
    feature: SensorFeatureReadiness
  ) -> SensorReadiness {
    SensorReadiness(
      hardwarePresence: presence,
      decoder: .notApplicable,
      readPath: readPath,
      stream: stream,
      feature: feature
    )
  }

  private func stateChannel(
    id: String,
    label: String,
    enabled: Bool,
    enabledText: String,
    disabledText: String,
    kind: SensorValueKind = .raw
  ) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: enabled ? 1 : 0,
      formattedValue: enabled ? enabledText : disabledText,
      kind: kind
    )
  }

  private func numericChannel(
    _ id: String,
    _ label: String,
    _ value: Double,
    _ unit: String?,
    kind: SensorValueKind = .raw
  ) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: value,
      formattedValue: SensorFormatting.decimal(
        value, fractionDigits: value.rounded() == value ? 0 : 1),
      unit: unit,
      kind: kind
    )
  }

  private func textChannel(_ id: String, _ label: String, _ value: String) -> SensorChannel {
    SensorChannel(id: id, label: label, formattedValue: value)
  }
}
