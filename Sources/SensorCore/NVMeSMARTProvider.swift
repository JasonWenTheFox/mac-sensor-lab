import CNVMeSMART
import Foundation

struct NVMeSMARTCounterReading: Equatable, Sendable {
  let dataUnitsRead: UInt128Counter
  let dataUnitsWritten: UInt128Counter
  let hostReadCommands: UInt128Counter
  let hostWriteCommands: UInt128Counter
  let controllerBusyTime: UInt128Counter
  let powerCycles: UInt128Counter
  let powerOnHours: UInt128Counter
  let unsafeShutdowns: UInt128Counter
  let mediaErrors: UInt128Counter
  let errorInformationLogEntries: UInt128Counter

  static let zero = NVMeSMARTCounterReading(
    dataUnitsRead: .zero,
    dataUnitsWritten: .zero,
    hostReadCommands: .zero,
    hostWriteCommands: .zero,
    controllerBusyTime: .zero,
    powerCycles: .zero,
    powerOnHours: .zero,
    unsafeShutdowns: .zero,
    mediaErrors: .zero,
    errorInformationLogEntries: .zero
  )
}

struct NVMeSMARTReading: Equatable, Sendable {
  let criticalWarning: UInt8
  let temperatureKelvin: UInt16
  let availableSpare: UInt8
  let availableSpareThreshold: UInt8
  let percentageUsed: UInt8
  let counters: NVMeSMARTCounterReading

  init(
    criticalWarning: UInt8,
    temperatureKelvin: UInt16,
    availableSpare: UInt8,
    availableSpareThreshold: UInt8,
    percentageUsed: UInt8,
    counters: NVMeSMARTCounterReading = .zero
  ) {
    self.criticalWarning = criticalWarning
    self.temperatureKelvin = temperatureKelvin
    self.availableSpare = availableSpare
    self.availableSpareThreshold = availableSpareThreshold
    self.percentageUsed = percentageUsed
    self.counters = counters
  }
}

enum NVMeSMARTReadResult: Equatable, Sendable {
  case success(NVMeSMARTReading)
  case systemVolumeUnavailable
  case smartUnavailable
  case interfaceUnavailable
  case permissionDenied
  case temporarilyUnavailable
  case readFailed
}

struct NVMeSMARTMetrics: Equatable, Sendable {
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
  let counters: NVMeSMARTCounterReading
  let dataReadCounterBytes: UInt128Counter?
  let dataWrittenCounterBytes: UInt128Counter?
  let invalidScalarFieldCount: Int
  let omittedCounterConversionCount: Int

  var hasWarning: Bool { criticalWarning != 0 }
  var invalidFieldCount: Int { invalidScalarFieldCount + omittedCounterConversionCount }
}

enum NVMeSMARTDecoder {
  private static let knownWarningMask: UInt8 = 0x1F
  private static let bytesPerDataUnit: UInt64 = 1_000 * 512

  static func decode(_ reading: NVMeSMARTReading) -> NVMeSMARTMetrics {
    var invalidScalarFieldCount = 0

    let temperatureCelsius: Double?
    switch reading.temperatureKelvin {
    case 0:
      temperatureCelsius = nil
    case 150...500:
      temperatureCelsius = Double(reading.temperatureKelvin) - 273.15
    default:
      temperatureCelsius = nil
      invalidScalarFieldCount += 1
    }

    let dataReadCounterBytes = reading.counters.dataUnitsRead.multiplied(by: bytesPerDataUnit)
    let dataWrittenCounterBytes = reading.counters.dataUnitsWritten.multiplied(
      by: bytesPerDataUnit)
    let omittedCounterConversionCount =
      (dataReadCounterBytes == nil ? 1 : 0) + (dataWrittenCounterBytes == nil ? 1 : 0)

    let availableSpare: UInt8?
    if reading.availableSpare <= 100 {
      availableSpare = reading.availableSpare
    } else {
      availableSpare = nil
      invalidScalarFieldCount += 1
    }

    let availableSpareThreshold: UInt8?
    if reading.availableSpareThreshold <= 100 {
      availableSpareThreshold = reading.availableSpareThreshold
    } else {
      availableSpareThreshold = nil
      invalidScalarFieldCount += 1
    }

    let warning = reading.criticalWarning
    return NVMeSMARTMetrics(
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
      counters: reading.counters,
      dataReadCounterBytes: dataReadCounterBytes,
      dataWrittenCounterBytes: dataWrittenCounterBytes,
      invalidScalarFieldCount: invalidScalarFieldCount,
      omittedCounterConversionCount: omittedCounterConversionCount
    )
  }
}

private enum NVMeSMARTSystemReader {
  static func read() -> NVMeSMARTReadResult {
    var data = MSLNVMeSMARTData()
    let status = MSLReadSystemNVMeSMARTData(&data)
    switch Int(status) {
    case MSL_NVME_SMART_STATUS_SUCCESS:
      return .success(
        NVMeSMARTReading(
          criticalWarning: data.critical_warning,
          temperatureKelvin: data.temperature_kelvin,
          availableSpare: data.available_spare,
          availableSpareThreshold: data.available_spare_threshold,
          percentageUsed: data.percentage_used,
          counters: NVMeSMARTCounterReading(
            dataUnitsRead: counter(data.data_units_read),
            dataUnitsWritten: counter(data.data_units_written),
            hostReadCommands: counter(data.host_read_commands),
            hostWriteCommands: counter(data.host_write_commands),
            controllerBusyTime: counter(data.controller_busy_time),
            powerCycles: counter(data.power_cycles),
            powerOnHours: counter(data.power_on_hours),
            unsafeShutdowns: counter(data.unsafe_shutdowns),
            mediaErrors: counter(data.media_errors),
            errorInformationLogEntries: counter(data.error_information_log_entries)
          )
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

  private static func counter(_ value: MSLUInt128) -> UInt128Counter {
    UInt128Counter(low: value.low, high: value.high)
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
      return successSnapshot(metrics: NVMeSMARTDecoder.decode(reading))
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

  private func successSnapshot(metrics: NVMeSMARTMetrics) -> SensorSnapshot {
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
    channels.append(contentsOf: counterChannels(metrics: metrics))

    var notes = [
      "No recognized warning bit is not a complete health assessment.",
      "Percentage used is a controller lifetime-use estimate; 100% does not mean failure and the value can exceed 100%.",
      "Composite temperature describes the controller and NVM, not room temperature.",
      "Data units are rounded up in groups of 1,000 × 512-byte units; converted counter bytes are exact for the reported unit count, not exact historical I/O bytes.",
      "Unsafe shutdowns and media errors are controller-reported cumulative facts, not attribution or failure predictions.",
      "Only SMARTReadData for the current system-volume whole disk is used; identify data, device names, serial numbers, paths, and detailed error logs are not read.",
    ]
    if metrics.invalidScalarFieldCount > 0 {
      notes.append("One or more scalar fields failed validation and were omitted.")
    }
    if metrics.omittedCounterConversionCount > 0 {
      notes.append(
        "One or more counter-byte conversions exceeded UInt128 and were omitted; raw counters remain available."
      )
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

  private func counterChannels(metrics: NVMeSMARTMetrics) -> [SensorChannel] {
    let counters = metrics.counters
    var channels = [
      counterChannel(
        id: "data_units_read",
        label: "Data units read",
        value: counters.dataUnitsRead,
        unit: "data units"
      )
    ]
    if let bytes = metrics.dataReadCounterBytes {
      channels.append(
        counterChannel(
          id: "data_read_counter_bytes",
          label: "Reported read counter bytes",
          value: bytes,
          unit: "bytes",
          kind: .derived
        )
      )
    }
    channels.append(
      counterChannel(
        id: "data_units_written",
        label: "Data units written",
        value: counters.dataUnitsWritten,
        unit: "data units"
      )
    )
    if let bytes = metrics.dataWrittenCounterBytes {
      channels.append(
        counterChannel(
          id: "data_written_counter_bytes",
          label: "Reported written counter bytes",
          value: bytes,
          unit: "bytes",
          kind: .derived
        )
      )
    }
    channels.append(contentsOf: [
      counterChannel(
        id: "host_read_commands",
        label: "Host read commands",
        value: counters.hostReadCommands,
        unit: "commands"
      ),
      counterChannel(
        id: "host_write_commands",
        label: "Host write commands",
        value: counters.hostWriteCommands,
        unit: "commands"
      ),
      counterChannel(
        id: "controller_busy_time",
        label: "Controller busy time",
        value: counters.controllerBusyTime,
        unit: "minutes"
      ),
      counterChannel(
        id: "power_cycles",
        label: "Power cycles",
        value: counters.powerCycles,
        unit: "cycles"
      ),
      counterChannel(
        id: "power_on_hours",
        label: "Power-on hours",
        value: counters.powerOnHours,
        unit: "hours"
      ),
      counterChannel(
        id: "unsafe_shutdowns",
        label: "Unsafe shutdown count",
        value: counters.unsafeShutdowns,
        unit: "events"
      ),
      counterChannel(
        id: "media_errors",
        label: "Media and data integrity errors",
        value: counters.mediaErrors,
        unit: "errors"
      ),
      counterChannel(
        id: "error_information_log_entries",
        label: "Error information log entries",
        value: counters.errorInformationLogEntries,
        unit: "entries"
      ),
    ])
    return channels
  }

  private func counterChannel(
    id: String,
    label: String,
    value: UInt128Counter,
    unit: String,
    kind: SensorValueKind = .raw
  ) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      formattedValue: value.decimalString,
      unit: unit,
      kind: kind
    )
  }
}
