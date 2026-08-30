import CoreFoundation
import Foundation
import IOKit.hid

private enum SPUSensorKind: Hashable {
  case accelerometer
  case gyroscope
  case ambientLight
}

private final class SPUSampleStore: @unchecked Sendable {
  private let lock = NSLock()
  private var reports: [SPUSensorKind: [UInt8]] = [:]

  func store(_ report: [UInt8], for kind: SPUSensorKind) {
    lock.withLock { reports[kind] = report }
  }

  func report(for kind: SPUSensorKind) -> [UInt8]? {
    lock.withLock { reports[kind] }
  }
}

private final class SPUCallbackContext {
  let kind: SPUSensorKind
  let store: SPUSampleStore

  init(kind: SPUSensorKind, store: SPUSampleStore) {
    self.kind = kind
    self.store = store
  }
}

struct SPUVectorReading {
  let x: Double
  let y: Double
  let z: Double
}

struct SPUAmbientReading {
  let intensity: Double?
  let spectralChannels: [UInt32]
}

enum SPUReportDecoder {
  static func vector(from report: [UInt8]) -> SPUVectorReading? {
    guard report.count == 22 else { return nil }
    return SPUVectorReading(
      x: scaledInt32(report, offset: 6),
      y: scaledInt32(report, offset: 10),
      z: scaledInt32(report, offset: 14)
    )
  }

  static func ambient(from report: [UInt8]) -> SPUAmbientReading? {
    guard report.count == 122 else { return nil }
    let rawIntensity = Double(Float(bitPattern: uint32LE(report, offset: 40)))
    return SPUAmbientReading(
      intensity: rawIntensity.isFinite ? rawIntensity : nil,
      spectralChannels: (0..<4).map { uint32LE(report, offset: 20 + $0 * 4) }
    )
  }

  private static func scaledInt32(_ bytes: [UInt8], offset: Int) -> Double {
    Double(Int32(bitPattern: uint32LE(bytes, offset: offset))) / 65_536
  }

  private static func uint32LE(_ bytes: [UInt8], offset: Int) -> UInt32 {
    UInt32(bytes[offset])
      | UInt32(bytes[offset + 1]) << 8
      | UInt32(bytes[offset + 2]) << 16
      | UInt32(bytes[offset + 3]) << 24
  }
}

private func spuInputReportCallback(
  context: UnsafeMutableRawPointer?,
  result: IOReturn,
  sender: UnsafeMutableRawPointer?,
  type: IOHIDReportType,
  reportID: UInt32,
  report: UnsafeMutablePointer<UInt8>,
  reportLength: CFIndex
) {
  guard result == kIOReturnSuccess,
    let context,
    reportLength > 0
  else { return }
  let callbackContext = Unmanaged<SPUCallbackContext>.fromOpaque(context).takeUnretainedValue()
  callbackContext.store.store(
    Array(UnsafeBufferPointer(start: report, count: Int(reportLength))),
    for: callbackContext.kind
  )
}

/// Best-effort, ordinary-permission Apple SPU reader.
///
/// The report layout is adapted and substantially rewritten from
/// olvvier/apple-silicon-accelerometer (MIT), commit
/// 203685640287449eaecf521c24d1f5e52486ecb7.
///
/// This provider deliberately omits the driver-property writes used by some
/// research projects to wake the SPU. It only listens for reports that macOS is
/// already publishing, then closes every HID handle it opened.
public struct SPULiveProvider: SensorProvider {
  private static let accessLock = NSLock()
  private static let snapshotCache = SPUSnapshotCache()

  public let metadata = SensorProviderMetadata(
    id: "motion.spu_live",
    name: "Motion & Ambient Light",
    category: .motion,
    source: "Apple SPU HID input reports",
    capability: .undocumented
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    let candidate = Self.accessLock.withLock { readSynchronously() }
    return Self.snapshotCache.resolve(candidate)
  }

  private func readSynchronously() -> SensorSnapshot {
    let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, noOptions)
    let matches: [[String: Any]] = [
      [kIOHIDPrimaryUsagePageKey as String: 0xFF00, kIOHIDPrimaryUsageKey as String: 3],
      [kIOHIDPrimaryUsagePageKey as String: 0xFF00, kIOHIDPrimaryUsageKey as String: 9],
      [kIOHIDPrimaryUsagePageKey as String: 0xFF00, kIOHIDPrimaryUsageKey as String: 4],
    ]
    IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

    let managerOpenResult = IOHIDManagerOpen(manager, noOptions)
    guard managerOpenResult == kIOReturnSuccess else {
      return failure(
        status: SPUHIDOpenFailure.status(for: [managerOpenResult]),
        summary: SPUHIDOpenFailure.summary(for: [managerOpenResult]),
        note: SPUHIDOpenFailure.note(for: [managerOpenResult])
      )
    }
    defer { IOHIDManagerClose(manager, noOptions) }

    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
      !devices.isEmpty
    else {
      return failure(status: .unavailable, summary: "No compatible Apple SPU report devices found")
    }

    let store = SPUSampleStore()
    var opened: [(device: IOHIDDevice, buffer: UnsafeMutablePointer<UInt8>)] = []
    var contexts: [SPUCallbackContext] = []
    var openErrors: [IOReturn] = []

    for device in devices {
      guard let kind = kind(for: device) else { continue }
      let openResult = IOHIDDeviceOpen(device, noOptions)
      guard openResult == kIOReturnSuccess else {
        openErrors.append(openResult)
        continue
      }

      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
      buffer.initialize(repeating: 0, count: 256)
      let context = SPUCallbackContext(kind: kind, store: store)
      contexts.append(context)
      IOHIDDeviceRegisterInputReportCallback(
        device,
        buffer,
        256,
        spuInputReportCallback,
        Unmanaged.passUnretained(context).toOpaque()
      )
      IOHIDDeviceScheduleWithRunLoop(
        device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
      opened.append((device, buffer))
    }

    guard !opened.isEmpty else {
      return failure(
        status: SPUHIDOpenFailure.status(for: openErrors),
        summary: SPUHIDOpenFailure.summary(for: openErrors),
        note: SPUHIDOpenFailure.note(for: openErrors)
      )
    }

    CFRunLoopRunInMode(.defaultMode, 0.25, false)

    for entry in opened {
      IOHIDDeviceUnscheduleFromRunLoop(
        entry.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
      IOHIDDeviceRegisterInputReportCallback(entry.device, entry.buffer, 256, nil, nil)
      IOHIDDeviceClose(entry.device, noOptions)
      entry.buffer.deinitialize(count: 256)
      entry.buffer.deallocate()
    }
    _fixLifetime(contexts)

    var channels: [SensorChannel] = []
    if let report = store.report(for: .accelerometer),
      let vector = SPUReportDecoder.vector(from: report)
    {
      let (x, y, z) = (vector.x, vector.y, vector.z)
      let magnitude = sqrt(x * x + y * y + z * z)
      let roll = atan2(y, z) * 180 / .pi
      let pitch = atan2(-x, sqrt(y * y + z * z)) * 180 / .pi
      channels += vectorChannels(
        prefix: "acceleration", label: "Acceleration", values: (x, y, z), unit: "g")
      channels.append(
        SensorChannel(
          id: "acceleration_magnitude", label: "Acceleration magnitude", value: magnitude,
          formattedValue: formatted(magnitude), unit: "g", kind: .derived))
      channels.append(
        SensorChannel(
          id: "level_roll", label: "Estimated roll", value: roll, formattedValue: formatted(roll),
          unit: "°", kind: .estimated, note: "Gravity-derived; axis orientation is model-dependent."
        ))
      channels.append(
        SensorChannel(
          id: "level_pitch", label: "Estimated pitch", value: pitch,
          formattedValue: formatted(pitch), unit: "°", kind: .estimated,
          note: "Gravity-derived; axis orientation is model-dependent."))
    }
    if let report = store.report(for: .gyroscope),
      let vector = SPUReportDecoder.vector(from: report)
    {
      let values = (vector.x, vector.y, vector.z)
      channels += vectorChannels(
        prefix: "angular_velocity", label: "Angular velocity", values: values, unit: "°/s")
    }
    if let report = store.report(for: .ambientLight),
      let ambient = SPUReportDecoder.ambient(from: report)
    {
      if let intensity = ambient.intensity {
        channels.append(
          SensorChannel(
            id: "ambient_intensity",
            label: "Ambient intensity",
            value: intensity,
            formattedValue: formatted(intensity),
            unit: nil,
            note: "Uncalibrated raw intensity; not asserted to be lux."
          ))
      }
      for (index, rawValue) in ambient.spectralChannels.enumerated() {
        let value = Double(rawValue)
        channels.append(
          SensorChannel(
            id: "ambient_spectral_\(index + 1)",
            label: "Spectral channel \(index + 1)",
            value: value,
            formattedValue: SensorFormatting.decimal(value, fractionDigits: 0),
            note: "Uncalibrated raw channel."
          ))
      }
    }

    guard !channels.isEmpty else {
      return failure(
        status: .degraded,
        summary: "Sensors detected, but macOS is not currently publishing reports"
      )
    }

    let groups = [
      channels.contains { $0.id.hasPrefix("acceleration_") } ? "accelerometer" : nil,
      channels.contains { $0.id.hasPrefix("angular_velocity_") } ? "gyroscope" : nil,
      channels.contains { $0.id.hasPrefix("ambient_") } ? "ambient light" : nil,
    ].compactMap { $0 }

    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "Live \(groups.joined(separator: ", ")) data",
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: []
    )
  }

  private func kind(for device: IOHIDDevice) -> SPUSensorKind? {
    let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?
      .intValue
    let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?
      .intValue
    switch (page, usage) {
    case (0xFF00, 3): return .accelerometer
    case (0xFF00, 9): return .gyroscope
    case (0xFF00, 4): return .ambientLight
    default: return nil
    }
  }

  private func vectorChannels(
    prefix: String,
    label: String,
    values: (Double, Double, Double),
    unit: String
  ) -> [SensorChannel] {
    zip(["x", "y", "z"], [values.0, values.1, values.2]).map { axis, value in
      SensorChannel(
        id: "\(prefix)_\(axis)",
        label: "\(label) \(axis.uppercased())",
        value: value,
        formattedValue: formatted(value),
        unit: unit
      )
    }
  }

  private func formatted(_ value: Double) -> String {
    SensorFormatting.decimal(value, fractionDigits: 3)
  }

  private func failure(
    status: SensorStatus,
    summary: String,
    note: String? = nil
  ) -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: status,
      source: metadata.source,
      capability: metadata.capability,
      notes: [note].compactMap { $0 }
    )
  }
}
