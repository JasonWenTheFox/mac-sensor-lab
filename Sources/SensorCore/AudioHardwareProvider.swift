import CoreAudio
import Foundation

enum AudioHardwareTransport: Equatable, Sendable {
  case builtIn
  case aggregate
  case virtual
  case pci
  case usb
  case fireWire
  case bluetooth
  case bluetoothLE
  case hdmi
  case displayPort
  case airPlay
  case avb
  case thunderbolt
  case continuityCaptureWired
  case continuityCaptureWireless

  init?(rawValue: UInt32) {
    switch rawValue {
    case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
    case kAudioDeviceTransportTypeAggregate: self = .aggregate
    case kAudioDeviceTransportTypeVirtual: self = .virtual
    case kAudioDeviceTransportTypePCI: self = .pci
    case kAudioDeviceTransportTypeUSB: self = .usb
    case kAudioDeviceTransportTypeFireWire: self = .fireWire
    case kAudioDeviceTransportTypeBluetooth: self = .bluetooth
    case kAudioDeviceTransportTypeBluetoothLE: self = .bluetoothLE
    case kAudioDeviceTransportTypeHDMI: self = .hdmi
    case kAudioDeviceTransportTypeDisplayPort: self = .displayPort
    case kAudioDeviceTransportTypeAirPlay: self = .airPlay
    case kAudioDeviceTransportTypeAVB: self = .avb
    case kAudioDeviceTransportTypeThunderbolt: self = .thunderbolt
    case kAudioDeviceTransportTypeContinuityCaptureWired: self = .continuityCaptureWired
    case kAudioDeviceTransportTypeContinuityCaptureWireless:
      self = .continuityCaptureWireless
    default: return nil
    }
  }

  var displayName: String {
    switch self {
    case .builtIn: "Built-in"
    case .aggregate: "Aggregate"
    case .virtual: "Virtual"
    case .pci: "PCI"
    case .usb: "USB"
    case .fireWire: "FireWire"
    case .bluetooth: "Bluetooth"
    case .bluetoothLE: "Bluetooth LE"
    case .hdmi: "HDMI"
    case .displayPort: "DisplayPort"
    case .airPlay: "AirPlay"
    case .avb: "AVB"
    case .thunderbolt: "Thunderbolt"
    case .continuityCaptureWired: "Continuity Camera (wired)"
    case .continuityCaptureWireless: "Continuity Camera (wireless)"
    }
  }
}

struct AudioHardwareDeviceReading: Equatable, Sendable {
  let isAlive: Bool?
  let transport: AudioHardwareTransport?
  let inputChannelCount: Int?
  let outputChannelCount: Int?
  let nominalSampleRate: Double?
  let inputLatencyFrames: Int?
  let outputLatencyFrames: Int?
}

enum AudioHardwareDefaultEndpoint: Equatable, Sendable {
  case none
  case unavailable
  case reported(AudioHardwareDeviceReading)
}

struct AudioHardwareInventoryReading: Equatable, Sendable {
  let devices: [AudioHardwareDeviceReading]
  let defaultInput: AudioHardwareDefaultEndpoint
  let defaultOutput: AudioHardwareDefaultEndpoint
}

enum AudioHardwareReadResult: Equatable, Sendable {
  case success(AudioHardwareInventoryReading)
  case temporarilyUnavailable
  case permissionDenied
  case failed
}

enum AudioHardwareMeasurements {
  static let maximumDeviceCount = 256
  static let maximumBufferListBytes = 65_536
  static let maximumBuffersPerDirection = 256
  static let bufferListHeaderBytes =
    MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.stride

  static func bufferListByteCount(bufferCount: Int) -> Int? {
    guard (0...maximumBuffersPerDirection).contains(bufferCount) else { return nil }
    let (buffersBytes, overflow) = bufferCount.multipliedReportingOverflow(
      by: MemoryLayout<AudioBuffer>.stride
    )
    guard !overflow else { return nil }
    let (totalBytes, additionOverflow) = bufferListHeaderBytes.addingReportingOverflow(buffersBytes)
    guard !additionOverflow, totalBytes <= maximumBufferListBytes else { return nil }
    return totalBytes
  }

  static func channelCount(_ value: Int?) -> Int? {
    guard let value, (0...1_024).contains(value) else { return nil }
    return value
  }

  static func sampleRate(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (1...4_000_000).contains(value) else { return nil }
    return value
  }

  static func latencyFrames(_ value: Int?) -> Int? {
    guard let value, (0...10_000_000).contains(value) else { return nil }
    return value
  }
}

private enum CoreAudioDefaultSelection {
  case none
  case unavailable
  case reported(AudioDeviceID)
}

private enum CoreAudioDeviceListResult {
  case success([AudioDeviceID])
  case malformed
  case failure(OSStatus)
}

private enum CoreAudioHardwareReader {
  static func read() -> AudioHardwareReadResult {
    switch deviceIDs() {
    case .malformed:
      return .failed
    case .failure(let status):
      return classifiedFailure(status)
    case .success(let deviceIDs):
      let defaultInput = defaultSelection(kAudioHardwarePropertyDefaultInputDevice)
      let defaultOutput = defaultSelection(kAudioHardwarePropertyDefaultOutputDevice)
      var readingsByID: [AudioDeviceID: AudioHardwareDeviceReading] = [:]
      for deviceID in deviceIDs {
        readingsByID[deviceID] = deviceReading(deviceID)
      }
      return .success(
        AudioHardwareInventoryReading(
          devices: deviceIDs.compactMap { readingsByID[$0] },
          defaultInput: endpoint(defaultInput, readingsByID: readingsByID),
          defaultOutput: endpoint(defaultOutput, readingsByID: readingsByID)
        )
      )
    }
  }

  private static func deviceIDs() -> CoreAudioDeviceListResult {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let sizeStatus = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
    )
    guard sizeStatus == kAudioHardwareNoError else { return .failure(sizeStatus) }
    guard dataSize % UInt32(MemoryLayout<AudioDeviceID>.stride) == 0 else {
      return .malformed
    }
    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
    guard count <= AudioHardwareMeasurements.maximumDeviceCount else { return .malformed }
    guard count > 0 else { return .success([]) }

    var deviceIDs = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
    let dataStatus = deviceIDs.withUnsafeMutableBytes { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return OSStatus(kAudioHardwareBadPropertySizeError)
      }
      return AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize,
        baseAddress
      )
    }
    guard dataStatus == kAudioHardwareNoError else { return .failure(dataStatus) }
    guard dataSize % UInt32(MemoryLayout<AudioDeviceID>.stride) == 0,
      Int(dataSize) <= count * MemoryLayout<AudioDeviceID>.stride
    else { return .malformed }
    let actualCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
    return .success(
      Array(deviceIDs.prefix(actualCount)).filter { $0 != AudioDeviceID(kAudioObjectUnknown) }
    )
  }

  private static func defaultSelection(
    _ selector: AudioObjectPropertySelector
  ) -> CoreAudioDefaultSelection {
    guard
      let deviceID: AudioDeviceID = scalar(
        objectID: AudioObjectID(kAudioObjectSystemObject), selector: selector,
        scope: kAudioObjectPropertyScopeGlobal, initialValue: kAudioObjectUnknown
      )
    else { return .unavailable }
    return deviceID == AudioDeviceID(kAudioObjectUnknown) ? .none : .reported(deviceID)
  }

  private static func endpoint(
    _ selection: CoreAudioDefaultSelection,
    readingsByID: [AudioDeviceID: AudioHardwareDeviceReading]
  ) -> AudioHardwareDefaultEndpoint {
    switch selection {
    case .none: .none
    case .unavailable: .unavailable
    case .reported(let deviceID):
      readingsByID[deviceID].map(AudioHardwareDefaultEndpoint.reported) ?? .unavailable
    }
  }

  private static func deviceReading(_ deviceID: AudioDeviceID) -> AudioHardwareDeviceReading {
    let aliveRaw: UInt32? = scalar(
      objectID: deviceID, selector: kAudioDevicePropertyDeviceIsAlive,
      scope: kAudioObjectPropertyScopeGlobal, initialValue: 0
    )
    let transportRaw: UInt32? = scalar(
      objectID: deviceID, selector: kAudioDevicePropertyTransportType,
      scope: kAudioObjectPropertyScopeGlobal, initialValue: 0
    )
    let sampleRateRaw: Float64? = scalar(
      objectID: deviceID, selector: kAudioDevicePropertyNominalSampleRate,
      scope: kAudioObjectPropertyScopeGlobal, initialValue: 0
    )
    let inputLatencyRaw: UInt32? = scalar(
      objectID: deviceID, selector: kAudioDevicePropertyLatency,
      scope: kAudioObjectPropertyScopeInput, initialValue: 0
    )
    let outputLatencyRaw: UInt32? = scalar(
      objectID: deviceID, selector: kAudioDevicePropertyLatency,
      scope: kAudioObjectPropertyScopeOutput, initialValue: 0
    )
    return AudioHardwareDeviceReading(
      isAlive: aliveRaw.map { $0 != 0 },
      transport: transportRaw.flatMap(AudioHardwareTransport.init(rawValue:)),
      inputChannelCount: streamChannelCount(deviceID, scope: kAudioObjectPropertyScopeInput),
      outputChannelCount: streamChannelCount(deviceID, scope: kAudioObjectPropertyScopeOutput),
      nominalSampleRate: AudioHardwareMeasurements.sampleRate(sampleRateRaw),
      inputLatencyFrames: AudioHardwareMeasurements.latencyFrames(inputLatencyRaw.map(Int.init)),
      outputLatencyFrames: AudioHardwareMeasurements.latencyFrames(outputLatencyRaw.map(Int.init))
    )
  }

  private static func streamChannelCount(
    _ deviceID: AudioDeviceID,
    scope: AudioObjectPropertyScope
  ) -> Int? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let headerBytes = AudioHardwareMeasurements.bufferListHeaderBytes
    guard
      AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        == kAudioHardwareNoError,
      dataSize >= UInt32(headerBytes),
      dataSize <= UInt32(AudioHardwareMeasurements.maximumBufferListBytes)
    else { return nil }

    let allocationBytes = max(Int(dataSize), MemoryLayout<AudioBufferList>.size)
    let storage = UnsafeMutableRawPointer.allocate(
      byteCount: allocationBytes, alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { storage.deallocate() }
    storage.initializeMemory(as: UInt8.self, repeating: 0, count: allocationBytes)
    guard
      AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, storage)
        == kAudioHardwareNoError,
      dataSize >= UInt32(headerBytes),
      dataSize <= UInt32(AudioHardwareMeasurements.maximumBufferListBytes)
    else { return nil }

    let pointer = storage.assumingMemoryBound(to: AudioBufferList.self)
    let bufferCount = Int(pointer.pointee.mNumberBuffers)
    guard
      let requiredBytes = AudioHardwareMeasurements.bufferListByteCount(bufferCount: bufferCount)
    else { return nil }
    guard requiredBytes <= Int(dataSize) else { return nil }

    var channelCount = 0
    for buffer in UnsafeMutableAudioBufferListPointer(pointer) {
      let (next, overflow) = channelCount.addingReportingOverflow(Int(buffer.mNumberChannels))
      guard !overflow, next <= 1_024 else { return nil }
      channelCount = next
    }
    return AudioHardwareMeasurements.channelCount(channelCount)
  }

  private static func scalar<T>(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope,
    initialValue: T
  ) -> T? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    var value = initialValue
    var dataSize = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer)
    }
    guard status == kAudioHardwareNoError, dataSize == UInt32(MemoryLayout<T>.size) else {
      return nil
    }
    return value
  }

  private static func classifiedFailure(_ status: OSStatus) -> AudioHardwareReadResult {
    switch status {
    case kAudioDevicePermissionsError:
      .permissionDenied
    case kAudioHardwareNotReadyError, kAudioHardwareBadPropertySizeError,
      kAudioHardwareBadObjectError, kAudioHardwareBadDeviceError:
      .temporarilyUnavailable
    default:
      .failed
    }
  }
}

public struct AudioHardwareProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "hardware.audio",
    name: "Audio Hardware",
    category: .system,
    source: "Core Audio hardware properties",
    capability: .publicAPI,
    domain: .audio,
    accessLevel: .publicOrdinary,
    compatibilityConfidence: .documentedPlatformContract
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    snapshot(result: CoreAudioHardwareReader.read())
  }

  func snapshot(result: AudioHardwareReadResult) -> SensorSnapshot {
    switch result {
    case .temporarilyUnavailable:
      return failureSnapshot(
        summary: "Audio hardware list was temporarily unavailable", status: .degraded,
        presence: .unknown, readPath: .limited, feature: .partial
      )
    case .permissionDenied:
      return failureSnapshot(
        summary: "Core Audio hardware property access was denied", status: .permissionRequired,
        presence: .unknown, readPath: .permissionRequired, feature: .blocked
      )
    case .failed:
      return failureSnapshot(
        summary: "Audio hardware properties could not be read", status: .error,
        presence: .unknown, readPath: .failed, feature: .unknown
      )
    case .success(let reading):
      return snapshot(reading: reading)
    }
  }

  private func snapshot(reading: AudioHardwareInventoryReading) -> SensorSnapshot {
    let devices = Array(reading.devices.prefix(AudioHardwareMeasurements.maximumDeviceCount))
    guard !devices.isEmpty else {
      return failureSnapshot(
        summary: "No audio devices were reported", status: .unavailable,
        presence: .absent, readPath: .ready, feature: .unsupported
      )
    }

    var channels = [integerChannel("device_count", "Audio devices", devices.count)]
    var partial = reading.devices.count > AudioHardwareMeasurements.maximumDeviceCount

    let aliveValues = devices.compactMap(\.isAlive)
    if aliveValues.count == devices.count {
      channels.append(
        integerChannel(
          "alive_device_count", "Available audio devices", aliveValues.count(where: { $0 }))
      )
      partial = partial || aliveValues.contains(false)
    } else {
      partial = true
    }

    let inputCounts = devices.compactMap {
      AudioHardwareMeasurements.channelCount($0.inputChannelCount)
    }
    let outputCounts = devices.compactMap {
      AudioHardwareMeasurements.channelCount($0.outputChannelCount)
    }
    let hasCompleteDirectionCounts =
      inputCounts.count == devices.count && outputCounts.count == devices.count
    if hasCompleteDirectionCounts {
      channels.append(
        integerChannel(
          "input_device_count", "Input-capable audio devices", inputCounts.count(where: { $0 > 0 }))
      )
      channels.append(
        integerChannel(
          "output_device_count", "Output-capable audio devices",
          outputCounts.count(where: { $0 > 0 }))
      )
      channels.append(
        integerChannel(
          "duplex_device_count", "Duplex audio devices",
          zip(inputCounts, outputCounts).count(where: { $0 > 0 && $1 > 0 })
        )
      )
    } else {
      partial = true
    }

    appendEndpoint(
      reading.defaultInput, prefix: "default_input", label: "Default input", direction: .input,
      channels: &channels, partial: &partial
    )
    appendEndpoint(
      reading.defaultOutput, prefix: "default_output", label: "Default output",
      direction: .output, channels: &channels, partial: &partial
    )

    let summary: String
    if hasCompleteDirectionCounts {
      let deviceWord = devices.count == 1 ? "device" : "devices"
      summary =
        "\(devices.count) \(deviceWord) • \(inputCounts.count(where: { $0 > 0 })) input • \(outputCounts.count(where: { $0 > 0 })) output"
    } else {
      summary = devices.count == 1 ? "1 audio device" : "\(devices.count) audio devices"
    }
    let status: SensorStatus = partial ? .degraded : .available
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: status,
      source: metadata.source,
      capability: metadata.capability,
      domain: metadata.domain,
      accessLevel: metadata.accessLevel,
      compatibilityConfidence: metadata.compatibilityConfidence,
      readiness: SensorReadiness(
        hardwarePresence: .present,
        decoder: .notApplicable,
        readPath: partial ? .limited : .ready,
        stream: .notApplicable,
        feature: partial ? .partial : .ready
      ),
      channels: channels,
      notes: privacyNotes
        + (partial
          ? ["One or more Core Audio properties were unavailable or invalid and were omitted."]
          : [])
    )
  }

  private enum EndpointDirection {
    case input
    case output
  }

  private func appendEndpoint(
    _ endpoint: AudioHardwareDefaultEndpoint,
    prefix: String,
    label: String,
    direction: EndpointDirection,
    channels: inout [SensorChannel],
    partial: inout Bool
  ) {
    switch endpoint {
    case .unavailable:
      partial = true
    case .none:
      channels.append(booleanChannel("\(prefix)_present", "\(label) reported", false))
    case .reported(let device):
      channels.append(booleanChannel("\(prefix)_present", "\(label) reported", true))
      if let transport = device.transport {
        channels.append(
          textChannel("\(prefix)_transport", "\(label) connection", transport.displayName)
        )
      } else {
        partial = true
      }
      let channelCount = AudioHardwareMeasurements.channelCount(
        direction == .input ? device.inputChannelCount : device.outputChannelCount
      )
      if let channelCount {
        channels.append(
          integerChannel("\(prefix)_channels", "\(label) channels", channelCount)
        )
      } else {
        partial = true
      }
      if let sampleRate = AudioHardwareMeasurements.sampleRate(device.nominalSampleRate) {
        channels.append(
          numberChannel(
            "\(prefix)_sample_rate", "\(label) nominal sample rate", sampleRate, unit: "Hz")
        )
      } else {
        partial = true
      }
      let latency = AudioHardwareMeasurements.latencyFrames(
        direction == .input ? device.inputLatencyFrames : device.outputLatencyFrames
      )
      if let latency {
        channels.append(
          integerChannel("\(prefix)_latency", "\(label) device latency", latency, unit: "frames")
        )
      } else {
        partial = true
      }
    }
  }

  private func failureSnapshot(
    summary: String,
    status: SensorStatus,
    presence: SensorHardwarePresence,
    readPath: SensorReadPathReadiness,
    feature: SensorFeatureReadiness
  ) -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: status,
      source: metadata.source,
      capability: metadata.capability,
      domain: metadata.domain,
      accessLevel: metadata.accessLevel,
      compatibilityConfidence: metadata.compatibilityConfidence,
      readiness: SensorReadiness(
        hardwarePresence: presence,
        decoder: .notApplicable,
        readPath: readPath,
        stream: .notApplicable,
        feature: feature
      ),
      notes: privacyNotes
    )
  }

  private var privacyNotes: [String] {
    [
      "Core Audio device handles are used only inside one read and are never stored or exported.",
      "Device UID, model UID, name, manufacturer, icon, clock domain, and free-form driver text are not read.",
      "This provider only queries hardware properties; it does not open an audio stream, capture samples, record audio, or request microphone permission.",
      "Nominal sample rate is the device's current configured rate; device latency excludes additional stream and safety-offset latency.",
    ]
  }

  private func integerChannel(
    _ id: String, _ label: String, _ value: Int, unit: String? = nil
  ) -> SensorChannel {
    SensorChannel(
      id: id, label: label, value: Double(value), formattedValue: String(value), unit: unit
    )
  }

  private func numberChannel(
    _ id: String, _ label: String, _ value: Double, unit: String
  ) -> SensorChannel {
    SensorChannel(
      id: id, label: label, value: value,
      formattedValue: SensorFormatting.decimal(
        value, fractionDigits: value.rounded() == value ? 0 : 2),
      unit: unit
    )
  }

  private func booleanChannel(_ id: String, _ label: String, _ value: Bool) -> SensorChannel {
    SensorChannel(
      id: id, label: label, value: value ? 1 : 0,
      formattedValue: value ? "Yes" : "No"
    )
  }

  private func textChannel(_ id: String, _ label: String, _ value: String) -> SensorChannel {
    SensorChannel(id: id, label: label, formattedValue: value)
  }
}
