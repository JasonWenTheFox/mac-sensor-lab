import CNVMeSMART
import Foundation

struct NVMeSMARTScalarReading: Equatable, Sendable {
  let criticalWarning: UInt8
  let temperatureKelvin: UInt16
  let availableSpare: UInt8
  let availableSpareThreshold: UInt8
  let percentageUsed: UInt8
}

enum NVMeSMARTReadResult: Equatable, Sendable {
  case success(NVMeSMARTScalarReading)
  case systemVolumeUnavailable
  case smartUnavailable
  case interfaceUnavailable
  case permissionDenied
  case temporarilyUnavailable
  case readFailed
}

struct NVMeSMARTScalarMetrics: Equatable, Sendable {
  let criticalWarning: UInt8
  let availableSpareBelowThreshold: Bool
  let temperatureThresholdExceeded: Bool
  let reliabilityDegraded: Bool
  let mediaReadOnly: Bool
  let volatileMemoryBackupFailed: Bool
  let unknownWarningPresent: Bool
  let compositeTemperatureCelsius: Double?
  let availableSpare: UInt8?
  let availableSpareThreshold: UInt8?
  let percentageUsed: UInt8
  let invalidFieldCount: Int

  var hasWarning: Bool { criticalWarning != 0 }
}

enum NVMeSMARTScalarDecoder {
  private static let knownWarningMask: UInt8 = 0x1F

  static func decode(_ reading: NVMeSMARTScalarReading) -> NVMeSMARTScalarMetrics {
    var invalidFieldCount = 0

    let temperatureCelsius: Double?
    switch reading.temperatureKelvin {
    case 0:
      temperatureCelsius = nil
    case 150...500:
      temperatureCelsius = Double(reading.temperatureKelvin) - 273.15
    default:
      temperatureCelsius = nil
      invalidFieldCount += 1
    }

    let availableSpare: UInt8?
    if reading.availableSpare <= 100 {
      availableSpare = reading.availableSpare
    } else {
      availableSpare = nil
      invalidFieldCount += 1
    }

    let availableSpareThreshold: UInt8?
    if reading.availableSpareThreshold <= 100 {
      availableSpareThreshold = reading.availableSpareThreshold
    } else {
      availableSpareThreshold = nil
      invalidFieldCount += 1
    }

    let warning = reading.criticalWarning
    return NVMeSMARTScalarMetrics(
      criticalWarning: warning,
      availableSpareBelowThreshold: warning & 0x01 != 0,
      temperatureThresholdExceeded: warning & 0x02 != 0,
      reliabilityDegraded: warning & 0x04 != 0,
      mediaReadOnly: warning & 0x08 != 0,
      volatileMemoryBackupFailed: warning & 0x10 != 0,
      unknownWarningPresent: warning & ~knownWarningMask != 0,
      compositeTemperatureCelsius: temperatureCelsius,
      availableSpare: availableSpare,
      availableSpareThreshold: availableSpareThreshold,
      percentageUsed: reading.percentageUsed,
      invalidFieldCount: invalidFieldCount
    )
  }
}

private enum NVMeSMARTSystemReader {
  static func read() -> NVMeSMARTReadResult {
    var data = MSLNVMeSMARTScalarData()
    let status = MSLReadSystemNVMeSMARTScalars(&data)
    switch Int(status) {
    case MSL_NVME_SMART_STATUS_SUCCESS:
      return .success(
        NVMeSMARTScalarReading(
          criticalWarning: data.critical_warning,
          temperatureKelvin: data.temperature_kelvin,
          availableSpare: data.available_spare,
          availableSpareThreshold: data.available_spare_threshold,
          percentageUsed: data.percentage_used
        )
      )
    case MSL_NVME_SMART_STATUS_SYSTEM_VOLUME_UNAVAILABLE: return .systemVolumeUnavailable
    case MSL_NVME_SMART_STATUS_SMART_UNAVAILABLE: return .smartUnavailable
    case MSL_NVME_SMART_STATUS_INTERFACE_UNAVAILABLE: return .interfaceUnavailable
    case MSL_NVME_SMART_STATUS_PERMISSION_DENIED: return .permissionDenied
    case MSL_NVME_SMART_STATUS_TEMPORARILY_UNAVAILABLE: return .temporarilyUnavailable
    default: return .readFailed
    }
  }
}

public final class NVMeSMARTProvider: SensorProvider, @unchecked Sendable {
  public let metadata = SensorProviderMetadata(
    id: "storage.nvme_health",
    name: "NVMe SMART",
    category: .storage,
    source: "Apple IONVMeSMARTInterface SMARTReadData",
    capability: .publicAPI,
    domain: .storage,
    accessLevel: .publicOrdinary,
    compatibilityConfidence: .singleModelObserved
  )

  static let minimumCacheInterval: TimeInterval = 60

  private let lock = NSLock()
  private let reader: () -> NVMeSMARTReadResult
  private let uptime: () -> TimeInterval
  private var cachedResult: (timestamp: TimeInterval, result: NVMeSMARTReadResult)?

  public convenience init() {
    self.init(
      reader: NVMeSMARTSystemReader.read,
      uptime: { ProcessInfo.processInfo.systemUptime }
    )
  }

  init(
    reader: @escaping () -> NVMeSMARTReadResult,
    uptime: @escaping () -> TimeInterval
  ) {
    self.reader = reader
    self.uptime = uptime
  }

  public func read() async -> SensorSnapshot {
    let now = uptime()
    let result = lock.withLock { () -> NVMeSMARTReadResult in
      if now.isFinite,
        let cachedResult,
        cachedResult.timestamp <= now,
        now - cachedResult.timestamp < Self.minimumCacheInterval
      {
        return cachedResult.result
      }

      let result = reader()
      if now.isFinite {
        cachedResult = (now, result)
      }
      return result
    }
    return snapshot(result: result)
  }

  func snapshot(result: NVMeSMARTReadResult) -> SensorSnapshot {
    switch result {
    case .success(let reading):
      return successSnapshot(metrics: NVMeSMARTScalarDecoder.decode(reading))
    case .systemVolumeUnavailable:
      return failureSnapshot(
        summary: "System-volume storage mapping was unavailable",
        status: .unavailable,
        readiness: SensorReadiness(
          hardwarePresence: .unknown,
          decoder: .notApplicable,
          readPath: .unavailable,
          stream: .notApplicable,
          feature: .unsupported
        )
      )
    case .smartUnavailable:
      return failureSnapshot(
        summary: "System disk does not expose NVMe SMART",
        status: .unavailable,
        readiness: SensorReadiness(
          hardwarePresence: .absent,
          decoder: .notApplicable,
          readPath: .unavailable,
          stream: .notApplicable,
          feature: .unsupported
        )
      )
    case .interfaceUnavailable:
      return failureSnapshot(
        summary: "NVMe SMART interface was unavailable",
        status: .unavailable,
        readiness: SensorReadiness(
          hardwarePresence: .present,
          decoder: .notApplicable,
          readPath: .unavailable,
          stream: .notApplicable,
          feature: .blocked
        )
      )
    case .permissionDenied:
      return failureSnapshot(
        summary: "NVMe SMART access was denied",
        status: .permissionRequired,
        readiness: SensorReadiness(
          hardwarePresence: .present,
          decoder: .notApplicable,
          readPath: .permissionRequired,
          stream: .notApplicable,
          feature: .blocked
        )
      )
    case .temporarilyUnavailable:
      return failureSnapshot(
        summary: "NVMe SMART device was temporarily unavailable",
        status: .degraded,
        readiness: SensorReadiness(
          hardwarePresence: .present,
          decoder: .notApplicable,
          readPath: .limited,
          stream: .notApplicable,
          feature: .partial
        )
      )
    case .readFailed:
      return failureSnapshot(
        summary: "NVMe SMART read failed",
        status: .error,
        readiness: SensorReadiness(
          hardwarePresence: .present,
          decoder: .notApplicable,
          readPath: .failed,
          stream: .notApplicable,
          feature: .blocked
        )
      )
    }
  }

  private func successSnapshot(metrics: NVMeSMARTScalarMetrics) -> SensorSnapshot {
    var channels = [
      SensorChannel(
        id: "critical_warning_bits",
        label: "Critical warning bits",
        value: Double(metrics.criticalWarning),
        formattedValue: String(format: "0x%02X", metrics.criticalWarning)
      ),
      booleanChannel(
        id: "available_spare_below_threshold",
        label: "Available spare below threshold",
        value: metrics.availableSpareBelowThreshold
      ),
      booleanChannel(
        id: "temperature_threshold_exceeded",
        label: "Composite temperature above critical threshold",
        value: metrics.temperatureThresholdExceeded
      ),
      booleanChannel(
        id: "reliability_degraded",
        label: "Reliability degraded warning",
        value: metrics.reliabilityDegraded
      ),
      booleanChannel(
        id: "media_read_only",
        label: "Media read-only warning",
        value: metrics.mediaReadOnly
      ),
      booleanChannel(
        id: "volatile_memory_backup_failed",
        label: "Volatile-memory backup warning",
        value: metrics.volatileMemoryBackupFailed
      ),
      booleanChannel(
        id: "unknown_warning_present",
        label: "Unknown warning bits present",
        value: metrics.unknownWarningPresent
      ),
    ]

    if let temperature = metrics.compositeTemperatureCelsius {
      channels.append(
        SensorChannel(
          id: "composite_temperature",
          label: "Composite temperature",
          value: temperature,
          formattedValue: SensorFormatting.decimal(temperature, fractionDigits: 1),
          unit: "°C",
          kind: .derived
        )
      )
    }
    if let spare = metrics.availableSpare {
      channels.append(percentChannel(id: "available_spare", label: "Available spare", value: spare))
    }
    if let threshold = metrics.availableSpareThreshold {
      channels.append(
        percentChannel(
          id: "available_spare_threshold",
          label: "Available spare threshold",
          value: threshold
        )
      )
    }
    channels.append(
      percentChannel(
        id: "percentage_used",
        label: "Percentage used estimate",
        value: metrics.percentageUsed,
        kind: .estimated
      )
    )

    var notes = [
      "No recognized warning bit is not a complete health assessment.",
      "Percentage used is a controller lifetime-use estimate; 100% does not mean failure and the value can exceed 100%.",
      "Composite temperature describes the controller and NVM, not room temperature.",
      "Only SMARTReadData for the current system-volume whole disk is used; identify data, device names, serial numbers, paths, and detailed error logs are not read.",
    ]
    if metrics.invalidFieldCount > 0 {
      notes.append("One or more scalar fields failed validation and were omitted.")
    }

    let summary: String
    if metrics.invalidFieldCount > 0 {
      summary = "NVMe SMART data partially available"
    } else if metrics.hasWarning {
      summary = "SMART warning bits reported"
    } else {
      summary = "No recognized SMART warning bits"
    }

    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: metrics.invalidFieldCount > 0 ? .degraded : .available,
      source: metadata.source,
      capability: metadata.capability,
      domain: metadata.domain,
      accessLevel: metadata.accessLevel,
      compatibilityConfidence: metadata.compatibilityConfidence,
      readiness: SensorReadiness(
        hardwarePresence: .present,
        decoder: .notApplicable,
        readPath: .ready,
        stream: .notApplicable,
        feature: metrics.invalidFieldCount > 0 ? .partial : .ready
      ),
      channels: channels,
      notes: notes
    )
  }

  private func failureSnapshot(
    summary: String,
    status: SensorStatus,
    readiness: SensorReadiness
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
      readiness: readiness,
      notes: ["No device identifier or system error text is exported."]
    )
  }

  private func booleanChannel(id: String, label: String, value: Bool) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: value ? 1 : 0,
      formattedValue: value ? "Yes" : "No",
      kind: .derived
    )
  }

  private func percentChannel(
    id: String,
    label: String,
    value: UInt8,
    kind: SensorValueKind = .raw
  ) -> SensorChannel {
    let numericValue = Double(value)
    return SensorChannel(
      id: id,
      label: label,
      value: numericValue,
      formattedValue: SensorFormatting.percentage(numericValue),
      unit: "%",
      kind: kind
    )
  }
}
