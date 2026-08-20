import Foundation
import XCTest

@testable import SensorCore

final class SensorCoreTests: XCTestCase {
  func testByteFormattingIsHumanReadable() {
    let value = SensorFormatting.bytes(1_073_741_824)
    XCTAssertTrue(value.contains("GB"))
    XCTAssertTrue(SensorFormatting.bytesPerSecond(1_024).contains("/s"))
  }

  func testCSVEscapesStructureAndSpreadsheetFormulas() {
    XCTAssertEqual(SensorFormatting.csvCell("plain"), "plain")
    XCTAssertEqual(SensorFormatting.csvCell("a,b"), "\"a,b\"")
    XCTAssertEqual(SensorFormatting.csvCell("a\"b"), "\"a\"\"b\"")
    XCTAssertEqual(SensorFormatting.csvCell("a\rb"), "\"a\rb\"")
    XCTAssertEqual(SensorFormatting.csvTextCell("=1+1"), "'=1+1")
    XCTAssertEqual(SensorFormatting.csvTextCell("+cmd"), "'+cmd")
    XCTAssertEqual(SensorFormatting.csvTextCell("-label"), "'-label")
    XCTAssertEqual(SensorFormatting.csvTextCell("@field"), "'@field")
    XCTAssertEqual(SensorFormatting.csvTextCell("42"), "42")
  }

  func testCSVExportProtectsTextButPreservesNegativeRawNumbers() {
    let snapshot = SensorSnapshot(
      id: "=provider",
      name: "+name",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "@source",
      capability: .publicAPI,
      channels: [
        SensorChannel(
          id: "-channel", label: "=label", value: -12.5,
          formattedValue: "-12.500", unit: "raw")
      ]
    )
    let text = String(decoding: SensorExportService.csvData([snapshot]), as: UTF8.self)
    XCTAssertTrue(
      text.contains("'=provider,'+name,available,'@source,'-channel,'=label,-12.5,'-12.500"))
  }

  func testExportDoesNotInventMachineIdentifiers() throws {
    let snapshot = SensorSnapshot(
      id: "test.provider",
      name: "Test",
      category: .diagnostics,
      summary: "Safe",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: [
        SensorChannel(id: "value", label: "Value", value: 1, formattedValue: "1")
      ]
    )
    let data = try SensorExportService.jsonData([snapshot])
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertFalse(text.localizedCaseInsensitiveContains("serial number"))
    XCTAssertFalse(text.localizedCaseInsensitiveContains("hardware uuid"))
    XCTAssertFalse(text.localizedCaseInsensitiveContains("provisioning udid"))
  }

  func testDiagnosticsExportContainsMetadataButNeverReadingsOrFreeText() throws {
    let snapshot = SensorSnapshot(
      id: "test.provider",
      name: "SENSITIVE_NAME",
      category: .environment,
      summary: "SENSITIVE_SUMMARY",
      status: .degraded,
      source: "SENSITIVE_SOURCE",
      capability: .undocumented,
      channels: [
        SensorChannel(
          id: "ambient_intensity",
          label: "SENSITIVE_LABEL",
          value: 123_456.789,
          formattedValue: "SENSITIVE_FORMATTED",
          unit: "raw",
          kind: .raw,
          note: "SENSITIVE_NOTE"
        )
      ],
      notes: ["SENSITIVE_SNAPSHOT_NOTE"],
      timestamp: Date(timeIntervalSince1970: 1_000)
    )

    let data = try SensorDiagnosticsExportService.jsonData(
      [snapshot],
      applicationVersion: "0.1.0-test",
      generatedAt: Date(timeIntervalSince1970: 2_000)
    )
    let report = try JSONDecoder.withISO8601.decode(SensorDiagnosticsReport.self, from: data)
    XCTAssertEqual(report.schemaVersion, 1)
    XCTAssertEqual(report.providers.first?.providerID, "test.provider")
    XCTAssertEqual(report.providers.first?.channels.first?.channelID, "ambient_intensity")
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertFalse(text.contains("SENSITIVE_"))
    XCTAssertFalse(text.contains("123456"))
    XCTAssertFalse(text.contains("1000"))
  }

  func testDiagnosticsExportRefusesUnsafeOrDuplicateIdentifiers() {
    let unsafe = SensorSnapshot(
      id: "system.device_uuid",
      name: "Fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: [
        SensorChannel(id: "value", label: "Value", value: 1, formattedValue: "1")
      ]
    )
    XCTAssertThrowsError(
      try SensorDiagnosticsExportService.jsonData(
        [unsafe],
        applicationVersion: "test"
      )
    ) { error in
      XCTAssertEqual(
        error as? SensorDiagnosticsExportError,
        .unsafeMetadata(code: .forbiddenIdentifier, path: "snapshots[0].id")
      )
    }

    let safe = SensorSnapshot(
      id: "test.provider",
      name: "Fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: [
        SensorChannel(id: "value", label: "Value", value: 1, formattedValue: "1")
      ]
    )
    XCTAssertThrowsError(
      try SensorDiagnosticsExportService.jsonData(
        [safe, safe],
        applicationVersion: "test"
      )
    ) { error in
      XCTAssertEqual(
        error as? SensorDiagnosticsExportError,
        .unsafeMetadata(code: .duplicateProviderIdentifier, path: "snapshots[1].id")
      )
    }
  }

  func testCSVExportKeepsRawAndFormattedValuesSeparate() {
    let snapshot = SensorSnapshot(
      id: "test.provider",
      name: "Test",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: [
        SensorChannel(
          id: "value", label: "Value", value: 12.5, formattedValue: "12.500", unit: "raw")
      ],
      timestamp: Date(timeIntervalSince1970: 1_000)
    )

    let text = String(decoding: SensorExportService.csvData([snapshot]), as: UTF8.self)
    XCTAssertTrue(text.hasPrefix(SensorCSVStreamEncoder.header))
    XCTAssertTrue(text.contains(",12.5,12.500,raw,raw,"))
    XCTAssertEqual(text.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 2)
  }

  func testCSVRecorderAppendsBatchesAndClosesCleanly() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("recording.csv")
    let recorder = try SensorCSVRecorder(destinationURL: destination)
    let snapshot = makeSPUSnapshot(
      status: .available,
      channels: [
        SensorChannel(
          id: "ambient_intensity", label: "Ambient intensity", value: 12,
          formattedValue: "12")
      ],
      timestamp: Date(timeIntervalSince1970: 1_000)
    )

    let firstProgress = try await recorder.append([snapshot])
    let secondProgress = try await recorder.append([snapshot])
    let finalProgress = try await recorder.finish()

    XCTAssertEqual(firstProgress.rowCount, 1)
    XCTAssertEqual(secondProgress.rowCount, 2)
    XCTAssertEqual(finalProgress, secondProgress)
    let text = try String(contentsOf: destination, encoding: .utf8)
    XCTAssertEqual(text.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 3)
    await assertThrowsErrorAsync(try await recorder.append([snapshot])) { error in
      XCTAssertEqual(error as? SensorCSVRecorderError, .alreadyClosed)
    }
  }

  func testCSVRecorderStopsBeforeExceedingByteLimit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("limited.csv")
    let limit = SensorCSVStreamEncoder.header.utf8.count + 1
    let recorder = try SensorCSVRecorder(destinationURL: destination, byteLimit: limit)
    let snapshot = makeSPUSnapshot(
      status: .available,
      channels: [
        SensorChannel(
          id: "ambient_intensity", label: "Ambient intensity", value: 12,
          formattedValue: "12")
      ],
      timestamp: Date(timeIntervalSince1970: 1_000)
    )

    await assertThrowsErrorAsync(try await recorder.append([snapshot])) { error in
      XCTAssertEqual(error as? SensorCSVRecorderError, .sizeLimitReached(limit: limit))
    }
    let progress = try await recorder.finish()
    XCTAssertEqual(progress.rowCount, 0)
    XCTAssertLessThanOrEqual(progress.byteCount, limit)
  }

  func testCSVRecorderReseeksAndRecountsAfterExternalAppend() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("externally-appended.csv")
    let recorder = try SensorCSVRecorder(destinationURL: destination)
    let externalMarker = Data("external-marker\n".utf8)
    let externalHandle = try FileHandle(forWritingTo: destination)
    try externalHandle.seekToEnd()
    try externalHandle.write(contentsOf: externalMarker)
    try externalHandle.synchronize()
    try externalHandle.close()

    let snapshot = makeSPUSnapshot(
      status: .available,
      channels: [
        SensorChannel(
          id: "ambient_intensity", label: "Ambient intensity", value: 12,
          formattedValue: "12")
      ],
      timestamp: Date(timeIntervalSince1970: 1_000)
    )
    let progress = try await recorder.append([snapshot])
    _ = try await recorder.finish()

    let data = try Data(contentsOf: destination)
    let text = String(decoding: data, as: UTF8.self)
    let markerRange = try XCTUnwrap(text.range(of: "external-marker\n"))
    let rowRange = try XCTUnwrap(
      text.range(of: "motion.spu_live", range: markerRange.upperBound..<text.endIndex))
    XCTAssertLessThan(markerRange.lowerBound, rowRange.lowerBound)
    XCTAssertEqual(progress.byteCount, data.count)
    XCTAssertEqual(progress.rowCount, 1)
  }

  func testCSVRecorderRejectsExternallyTruncatedDestination() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("externally-truncated.csv")
    let recorder = try SensorCSVRecorder(destinationURL: destination)
    let externalHandle = try FileHandle(forWritingTo: destination)
    try externalHandle.truncate(atOffset: 0)
    try externalHandle.close()
    let snapshot = makeSPUSnapshot(
      status: .available,
      timestamp: Date(timeIntervalSince1970: 1_000)
    )

    await assertThrowsErrorAsync(try await recorder.append([snapshot])) { error in
      XCTAssertEqual(error as? SensorCSVRecorderError, .destinationTruncated)
    }
    let progress = try await recorder.finish()
    XCTAssertEqual(progress.rowCount, 0)
    XCTAssertEqual(progress.byteCount, 0)
    XCTAssertEqual(try Data(contentsOf: destination).count, 0)
  }

  func testCSVRecorderDeduplicatesConcurrentSnapshotFlushes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("deduplicated.csv")
    let recorder = try SensorCSVRecorder(destinationURL: destination)
    let timestamp = Date(timeIntervalSince1970: 1_000)
    let snapshot = makeSPUSnapshot(
      status: .available,
      channels: [
        SensorChannel(
          id: "ambient_intensity", label: "Ambient intensity", value: 12,
          formattedValue: "12")
      ],
      timestamp: timestamp
    )

    async let first = recorder.appendNewSnapshots([snapshot])
    async let second = recorder.appendNewSnapshots([snapshot])
    _ = try await (first, second)
    let statusChange = makeSPUSnapshot(
      status: .degraded,
      channels: snapshot.channels,
      timestamp: timestamp
    )
    _ = try await recorder.appendNewSnapshots([statusChange])
    let progress = try await recorder.finish()

    XCTAssertEqual(progress.rowCount, 2)
    let text = try String(contentsOf: destination, encoding: .utf8)
    XCTAssertEqual(text.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 3)
  }

  func testSensorSeriesStatisticsIgnoreNonFiniteValues() throws {
    let statistics = try XCTUnwrap(
      SensorSeriesStatistics(values: [10, .nan, 20, .infinity, 30]))
    XCTAssertEqual(statistics.sampleCount, 3)
    XCTAssertEqual(statistics.latest, 30)
    XCTAssertEqual(statistics.minimum, 10)
    XCTAssertEqual(statistics.maximum, 30)
    XCTAssertEqual(statistics.average, 20)
    XCTAssertEqual(statistics.relativePosition ?? .nan, 1, accuracy: 0.000_001)
    XCTAssertNil(SensorSeriesStatistics(values: [.nan, .infinity]))
    XCTAssertNil(SensorSeriesStatistics(values: [5])?.relativePosition)
    let extremeStatistics = try XCTUnwrap(
      SensorSeriesStatistics(values: [-.greatestFiniteMagnitude, 0, .greatestFiniteMagnitude]))
    XCTAssertTrue(extremeStatistics.average.isFinite)
    XCTAssertEqual(extremeStatistics.average, 0, accuracy: 0.000_001)
    XCTAssertEqual(extremeStatistics.relativePosition ?? .nan, 1, accuracy: 0.000_001)
  }

  func testAmbientLuxCalibrationIsExplicitAndValidated() throws {
    let calibration = try XCTUnwrap(
      AmbientLuxCalibration(
        rawReference: 25,
        luxReference: 100,
        capturedAt: Date(timeIntervalSince1970: 1_000)
      ))
    XCTAssertEqual(calibration.scale, 4)
    XCTAssertEqual(try XCTUnwrap(calibration.estimatedLux(for: 12.5)), 50)
    let channel = try XCTUnwrap(calibration.estimatedChannel(for: 12.5))
    XCTAssertEqual(channel.id, "ambient_estimated_lux")
    XCTAssertEqual(channel.value, 50)
    XCTAssertEqual(channel.unit, "lux")
    XCTAssertEqual(channel.kind, .estimated)
    XCTAssertNil(calibration.estimatedLux(for: .nan))
    let encoded = try JSONEncoder().encode(calibration)
    XCTAssertEqual(try JSONDecoder().decode(AmbientLuxCalibration.self, from: encoded), calibration)
    let invalid = Data(
      "{\"rawReference\":0,\"luxReference\":100,\"capturedAt\":0}".utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(AmbientLuxCalibration.self, from: invalid))
    XCTAssertNil(AmbientLuxCalibration(rawReference: 0, luxReference: 100))
    XCTAssertNil(AmbientLuxCalibration(rawReference: 25, luxReference: -1))
    XCTAssertNil(
      AmbientLuxCalibration(
        rawReference: .leastNonzeroMagnitude,
        luxReference: .greatestFiniteMagnitude
      ))
  }

  func testAmbientCalibrationFileRoundTripsAndBoundsInput() throws {
    let calibration = try XCTUnwrap(
      AmbientLuxCalibration(
        rawReference: 25,
        luxReference: 100,
        capturedAt: Date(timeIntervalSince1970: 1_000)
      ))
    let data = try AmbientLuxCalibrationFileService.data(for: calibration)
    XCTAssertLessThan(data.count, AmbientLuxCalibrationFileService.maximumByteCount)
    XCTAssertEqual(
      try AmbientLuxCalibrationFileService.calibration(from: data),
      calibration
    )

    let oversized = Data(
      repeating: 0x20,
      count: AmbientLuxCalibrationFileService.maximumByteCount + 1
    )
    XCTAssertThrowsError(try AmbientLuxCalibrationFileService.calibration(from: oversized)) {
      XCTAssertEqual(
        $0 as? AmbientLuxCalibrationFileError,
        .fileTooLarge(maximumBytes: AmbientLuxCalibrationFileService.maximumByteCount)
      )
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let oversizedURL = directory.appendingPathComponent("oversized.json")
    try oversized.write(to: oversizedURL)
    XCTAssertThrowsError(try AmbientLuxCalibrationFileService.read(from: oversizedURL)) {
      XCTAssertEqual(
        $0 as? AmbientLuxCalibrationFileError,
        .fileTooLarge(maximumBytes: AmbientLuxCalibrationFileService.maximumByteCount)
      )
    }
    let remoteURL = try XCTUnwrap(URL(string: "https://example.invalid"))
    XCTAssertThrowsError(
      try AmbientLuxCalibrationFileService.read(from: remoteURL)
    ) {
      XCTAssertEqual($0 as? AmbientLuxCalibrationFileError, .invalidSource)
    }
  }

  func testRelativeAngleMeasurementPreservesDirection() throws {
    let opening = try XCTUnwrap(RelativeAngleMeasurement(current: 110, reference: 90))
    let closing = try XCTUnwrap(RelativeAngleMeasurement(current: 70, reference: 90))
    XCTAssertEqual(opening.delta, 20)
    XCTAssertEqual(closing.delta, -20)
    XCTAssertNil(RelativeAngleMeasurement(current: .nan, reference: 90))
    XCTAssertNil(
      RelativeAngleMeasurement(
        current: .greatestFiniteMagnitude,
        reference: -.greatestFiniteMagnitude
      ))
  }

  func testCPUUsageCalculatorUsesTickDeltas() throws {
    let previous = CPUTickSample(user: 100, system: 50, idle: 850, nice: 0)
    let current = CPUTickSample(user: 130, system: 70, idle: 900, nice: 0)
    XCTAssertEqual(
      try XCTUnwrap(CPUUsageCalculator.percentage(previous: previous, current: current)),
      50,
      accuracy: 0.000_001
    )
    XCTAssertNil(CPUUsageCalculator.percentage(previous: current, current: previous))
    XCTAssertNil(CPUUsageCalculator.percentage(previous: previous, current: previous))
  }

  func testNetworkRateCalculatorUsesMonotonicDeltas() throws {
    let previous = NetworkCounterSample(
      activeInterfaceCount: 2,
      receivedBytes: 1_000,
      sentBytes: 2_000,
      receivedPackets: 10,
      sentPackets: 20,
      timestamp: 100
    )
    let current = NetworkCounterSample(
      activeInterfaceCount: 2,
      receivedBytes: 3_000,
      sentBytes: 3_000,
      receivedPackets: 30,
      sentPackets: 30,
      timestamp: 102
    )
    let rates = try XCTUnwrap(NetworkRateCalculator.rates(previous: previous, current: current))
    XCTAssertEqual(rates.receivedBytesPerSecond, 1_000)
    XCTAssertEqual(rates.sentBytesPerSecond, 500)
    XCTAssertEqual(rates.receivedPacketsPerSecond, 10)
    XCTAssertEqual(rates.sentPacketsPerSecond, 5)
    XCTAssertNil(NetworkRateCalculator.rates(previous: current, current: previous))
    let changedTopology = NetworkCounterSample(
      activeInterfaceCount: 3,
      receivedBytes: current.receivedBytes,
      sentBytes: current.sentBytes,
      receivedPackets: current.receivedPackets,
      sentPackets: current.sentPackets,
      timestamp: current.timestamp + 1
    )
    XCTAssertNil(NetworkRateCalculator.rates(previous: current, current: changedTopology))
    let invalidTime = NetworkCounterSample(
      activeInterfaceCount: current.activeInterfaceCount,
      receivedBytes: current.receivedBytes,
      sentBytes: current.sentBytes,
      receivedPackets: current.receivedPackets,
      sentPackets: current.sentPackets,
      timestamp: .infinity
    )
    XCTAssertNil(NetworkRateCalculator.rates(previous: current, current: invalidTime))
    let overflowingRate = NetworkCounterSample(
      activeInterfaceCount: 1,
      receivedBytes: .max,
      sentBytes: .max,
      receivedPackets: .max,
      sentPackets: .max,
      timestamp: .leastNonzeroMagnitude
    )
    let zeroNetworkSample = NetworkCounterSample(
      activeInterfaceCount: 1,
      receivedBytes: 0,
      sentBytes: 0,
      receivedPackets: 0,
      sentPackets: 0,
      timestamp: 0
    )
    XCTAssertNil(
      NetworkRateCalculator.rates(previous: zeroNetworkSample, current: overflowingRate))
  }

  func testDiskIORateCalculatorUsesMonotonicDeltas() throws {
    let previous = DiskIOCounterSample(
      deviceCount: 1,
      bytesRead: 1_000,
      bytesWritten: 2_000,
      readOperations: 10,
      writeOperations: 20,
      timestamp: 100
    )
    let current = DiskIOCounterSample(
      deviceCount: 1,
      bytesRead: 5_000,
      bytesWritten: 4_000,
      readOperations: 30,
      writeOperations: 30,
      timestamp: 102
    )
    let rates = try XCTUnwrap(DiskIORateCalculator.rates(previous: previous, current: current))
    XCTAssertEqual(rates.readBytesPerSecond, 2_000)
    XCTAssertEqual(rates.writeBytesPerSecond, 1_000)
    XCTAssertEqual(rates.readOperationsPerSecond, 10)
    XCTAssertEqual(rates.writeOperationsPerSecond, 5)
    XCTAssertNil(DiskIORateCalculator.rates(previous: current, current: previous))
    let changedTopology = DiskIOCounterSample(
      deviceCount: 2,
      bytesRead: current.bytesRead,
      bytesWritten: current.bytesWritten,
      readOperations: current.readOperations,
      writeOperations: current.writeOperations,
      timestamp: current.timestamp + 1
    )
    XCTAssertNil(DiskIORateCalculator.rates(previous: current, current: changedTopology))
    let invalidTime = DiskIOCounterSample(
      deviceCount: current.deviceCount,
      bytesRead: current.bytesRead,
      bytesWritten: current.bytesWritten,
      readOperations: current.readOperations,
      writeOperations: current.writeOperations,
      timestamp: .infinity
    )
    XCTAssertNil(DiskIORateCalculator.rates(previous: current, current: invalidTime))
    let overflowingRate = DiskIOCounterSample(
      deviceCount: 1,
      bytesRead: .max,
      bytesWritten: .max,
      readOperations: .max,
      writeOperations: .max,
      timestamp: .leastNonzeroMagnitude
    )
    let zeroDiskSample = DiskIOCounterSample(
      deviceCount: 1,
      bytesRead: 0,
      bytesWritten: 0,
      readOperations: 0,
      writeOperations: 0,
      timestamp: 0
    )
    XCTAssertNil(DiskIORateCalculator.rates(previous: zeroDiskSample, current: overflowingRate))
  }

  func testSnapshotSearchMatchesProvidersAndNarrowsChannels() throws {
    let snapshot = SensorSnapshot(
      id: "storage.disk_io",
      name: "Disk Activity",
      category: .storage,
      summary: "Read 1 MB/s",
      status: .available,
      source: "IOKit statistics",
      capability: .publicAPI,
      channels: [
        SensorChannel(
          id: "disk_read_rate", label: "Read rate", value: 1,
          formattedValue: "1 MB/s", unit: "bytes/s", kind: .derived),
        SensorChannel(
          id: "disk_write_rate", label: "Write rate", value: 2,
          formattedValue: "2 MB/s", unit: "bytes/s", kind: .derived),
      ]
    )

    let providerMatch = try XCTUnwrap(
      SensorSnapshotSearch.filter([snapshot], query: "disk activity").first)
    XCTAssertEqual(providerMatch.channels.count, 2)
    let channelMatch = try XCTUnwrap(
      SensorSnapshotSearch.filter([snapshot], query: "write_rate").first)
    XCTAssertEqual(channelMatch.channels.map(\.id), ["disk_write_rate"])
    XCTAssertTrue(SensorSnapshotSearch.filter([snapshot], query: "microphone").isEmpty)
    XCTAssertEqual(SensorSnapshotSearch.filter([snapshot], query: "   "), [snapshot])
  }

  func testBatteryMeasurementsValidateCapacityAndTime() throws {
    XCTAssertEqual(
      try XCTUnwrap(BatteryMeasurements.chargePercentage(current: 4_000, maximum: 5_000)),
      80,
      accuracy: 0.000_001
    )
    XCTAssertNil(BatteryMeasurements.chargePercentage(current: nil, maximum: 5_000))
    XCTAssertNil(BatteryMeasurements.chargePercentage(current: -1, maximum: 5_000))
    XCTAssertNil(BatteryMeasurements.chargePercentage(current: 5_001, maximum: 5_000))
    XCTAssertNil(BatteryMeasurements.chargePercentage(current: 1, maximum: 0))
    XCTAssertNil(BatteryMeasurements.chargePercentage(current: .nan, maximum: 5_000))
    XCTAssertEqual(
      try XCTUnwrap(BatteryMeasurements.capacityRatio(nominal: 5_000, design: 6_250)),
      80,
      accuracy: 0.000_001
    )
    XCTAssertNil(BatteryMeasurements.capacityRatio(nominal: 5_000, design: 0))
    XCTAssertNil(BatteryMeasurements.capacityRatio(nominal: .nan, design: 6_250))
    XCTAssertNil(BatteryMeasurements.capacityRatio(nominal: .greatestFiniteMagnitude, design: 1))
    XCTAssertEqual(BatteryMeasurements.validMinutes(90), 90)
    XCTAssertNil(BatteryMeasurements.validMinutes(65_535))
    XCTAssertNil(BatteryMeasurements.validMinutes(-1))
    XCTAssertEqual(
      try XCTUnwrap(BatteryMeasurements.electricalPower(voltage: 12, current: -1.5)),
      -18,
      accuracy: 0.000_001
    )
    XCTAssertNil(BatteryMeasurements.electricalPower(voltage: nil, current: 1))
    XCTAssertNil(
      BatteryMeasurements.electricalPower(voltage: .greatestFiniteMagnitude, current: 2))
  }

  func testGPUPerformanceValueRejectsInvalidPercentages() {
    XCTAssertEqual(GPUPerformanceValue.percentage(64), 64)
    XCTAssertNil(GPUPerformanceValue.percentage(-1))
    XCTAssertNil(GPUPerformanceValue.percentage(101))
    XCTAssertNil(GPUPerformanceValue.percentage(.nan))
  }

  func testRegistryHasStableUniqueProviderIDs() {
    let ids = SensorProviderRegistry.providers().map(\.metadata.id)
    XCTAssertEqual(Set(ids).count, ids.count)
    XCTAssertGreaterThanOrEqual(ids.count, 14)
  }

  func testDemoPreferenceKeysAreIsolatedFromLiveMode() {
    let liveKeys = Set([
      SensorPreferenceKeys.samplingCadence(isDemoMode: false),
      SensorPreferenceKeys.ambientLuxCalibration(isDemoMode: false),
      SensorPreferenceKeys.lidHasReference(isDemoMode: false),
      SensorPreferenceKeys.lidReferenceAngle(isDemoMode: false),
    ])
    let demoKeys = Set([
      SensorPreferenceKeys.samplingCadence(isDemoMode: true),
      SensorPreferenceKeys.ambientLuxCalibration(isDemoMode: true),
      SensorPreferenceKeys.lidHasReference(isDemoMode: true),
      SensorPreferenceKeys.lidReferenceAngle(isDemoMode: true),
    ])

    XCTAssertEqual(liveKeys.count, 4)
    XCTAssertEqual(demoKeys.count, 4)
    XCTAssertTrue(liveKeys.isDisjoint(with: demoKeys))
    XCTAssertTrue(demoKeys.allSatisfy { $0.hasSuffix(".demo") })
    XCTAssertTrue(liveKeys.allSatisfy { !$0.hasSuffix(".demo") })
  }

  func testReadAllKeepsDuplicateProviderIDsVisibleForContractAudit() async {
    let provider = SensorDemoProviderRegistry.providers()[0]
    let providers: [any SensorProvider] = [provider, provider]

    let snapshots = await SensorProviderRegistry.readAll(providers)

    XCTAssertEqual(snapshots.count, 2)
    XCTAssertEqual(snapshots.map(\.id), [provider.metadata.id, provider.metadata.id])
    let duplicateIssues = SensorContractAudit.issues(
      providers: providers,
      snapshots: snapshots
    ).filter { $0.code == .duplicateProviderIdentifier }
    XCTAssertEqual(duplicateIssues.count, 2)
  }

  func testDemoRegistryIsCompleteFiniteAndClearlyLabeled() async {
    let providers = SensorDemoProviderRegistry.providers()
    XCTAssertEqual(providers.count, SensorProviderRegistry.providers().count)
    XCTAssertEqual(Set(providers.map(\.metadata.id)).count, providers.count)

    for provider in providers {
      XCTAssertEqual(provider.metadata.source, "Built-in deterministic demo fixture")
      let snapshot = await provider.read()
      XCTAssertEqual(snapshot.status, .available)
      XCTAssertEqual(snapshot.source, "Built-in deterministic demo fixture")
      XCTAssertTrue(snapshot.notes.contains("Synthetic demo data; not a hardware reading."))
      XCTAssertTrue(snapshot.channels.allSatisfy { $0.value?.isFinite ?? true })
    }

    let snapshots = await SensorProviderRegistry.readAll(providers)
    XCTAssertEqual(snapshots.map(\.id), providers.map(\.metadata.id))
  }

  func testContractAuditAcceptsDemoRegistryAndDetectsMetadataDrift() async {
    let providers = SensorDemoProviderRegistry.providers()
    var snapshots = await SensorProviderRegistry.readAll(providers)
    XCTAssertEqual(
      SensorContractAudit.issues(providers: providers, snapshots: snapshots),
      []
    )

    let original = snapshots[0]
    snapshots[0] = SensorSnapshot(
      id: original.id,
      name: "Drifted name",
      category: original.category,
      summary: original.summary,
      status: original.status,
      source: original.source,
      capability: original.capability,
      channels: original.channels,
      notes: original.notes,
      timestamp: original.timestamp
    )
    let driftIssues = SensorContractAudit.issues(providers: providers, snapshots: snapshots)
    XCTAssertEqual(driftIssues.map(\.code), [.providerMetadataMismatch])
    XCTAssertEqual(driftIssues.first?.path, "snapshots[0].name")

    snapshots[0] = SensorSnapshot(
      id: "system.alternate",
      name: original.name,
      category: original.category,
      summary: original.summary,
      status: original.status,
      source: original.source,
      capability: original.capability,
      channels: original.channels,
      notes: original.notes,
      timestamp: original.timestamp
    )
    let linkageCodes = Set(
      SensorContractAudit.issues(providers: providers, snapshots: snapshots).map(\.code))
    XCTAssertEqual(linkageCodes, [.missingProviderSnapshot, .unexpectedProviderIdentifier])
  }

  func testContractAuditRejectsMalformedSnapshotStructure() {
    let now = Date(timeIntervalSinceReferenceDate: 10_000)
    let malformed = SensorSnapshot(
      id: "Bad ID",
      name: "Fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: [
        SensorChannel(
          id: "duplicate", label: "One", value: .nan,
          formattedValue: "", unit: " "
        ),
        SensorChannel(
          id: "duplicate", label: "Two", value: 1,
          formattedValue: "1"
        ),
        SensorChannel(
          id: "device_uuid", label: "Forbidden", value: 1,
          formattedValue: "1"
        ),
      ],
      timestamp: now.addingTimeInterval(6)
    )
    let duplicate = SensorSnapshot(
      id: malformed.id,
      name: malformed.name,
      category: malformed.category,
      summary: malformed.summary,
      status: malformed.status,
      source: malformed.source,
      capability: malformed.capability,
      timestamp: now
    )

    let codes = Set(
      SensorContractAudit.issues(for: [malformed, duplicate], now: now).map(\.code))
    XCTAssertTrue(codes.contains(.invalidStableIdentifier))
    XCTAssertTrue(codes.contains(.duplicateProviderIdentifier))
    XCTAssertTrue(codes.contains(.duplicateChannelIdentifier))
    XCTAssertTrue(codes.contains(.forbiddenIdentifier))
    XCTAssertTrue(codes.contains(.nonFiniteValue))
    XCTAssertTrue(codes.contains(.emptyFormattedValue))
    XCTAssertTrue(codes.contains(.emptyUnit))
    XCTAssertTrue(codes.contains(.futureTimestamp))
  }

  func testSPUVectorReportDecoding() {
    var report = [UInt8](repeating: 0, count: 22)
    writeLittleEndian(UInt32(bitPattern: 65_536), to: &report, at: 6)
    writeLittleEndian(UInt32(bitPattern: -32_768), to: &report, at: 10)
    writeLittleEndian(UInt32(bitPattern: 131_072), to: &report, at: 14)

    guard let vector = SPUReportDecoder.vector(from: report) else {
      return XCTFail("Expected a decoded vector")
    }
    XCTAssertEqual(vector.x, 1, accuracy: 0.000_001)
    XCTAssertEqual(vector.y, -0.5, accuracy: 0.000_001)
    XCTAssertEqual(vector.z, 2, accuracy: 0.000_001)
    XCTAssertNil(SPUReportDecoder.vector(from: [0]))
  }

  func testSPUAmbientReportDecoding() {
    var report = [UInt8](repeating: 0, count: 122)
    for (index, value) in [100, 200, 300, 400].enumerated() {
      writeLittleEndian(UInt32(value), to: &report, at: 20 + index * 4)
    }
    writeLittleEndian(Float(12.5).bitPattern, to: &report, at: 40)

    guard let ambient = SPUReportDecoder.ambient(from: report) else {
      return XCTFail("Expected a decoded ambient-light report")
    }
    XCTAssertEqual(ambient.intensity ?? .nan, 12.5, accuracy: 0.000_001)
    XCTAssertEqual(ambient.spectralChannels, [100, 200, 300, 400])
    XCTAssertNil(SPUReportDecoder.ambient(from: [0]))
  }

  func testSPUOpenErrorClassificationDistinguishesContentionFromPermission() {
    XCTAssertEqual(
      SPUHIDOpenFailure.status(for: [kIOReturnNotPrivileged, kIOReturnNotPermitted]),
      .permissionRequired
    )
    XCTAssertEqual(
      SPUHIDOpenFailure.status(for: [kIOReturnExclusiveAccess]),
      .degraded
    )
    XCTAssertEqual(
      SPUHIDOpenFailure.status(for: [kIOReturnBusy, kIOReturnNotPermitted]),
      .degraded
    )
    XCTAssertEqual(SPUHIDOpenFailure.status(for: []), .unavailable)
  }

  func testSPUStabilizerKeepsRecentDataWithoutFakingFreshTimestamp() {
    let sampleTime = Date(timeIntervalSince1970: 1_000)
    let sample = makeSPUSnapshot(
      status: .available,
      channels: [
        SensorChannel(
          id: "ambient_intensity", label: "Ambient intensity", value: 12,
          formattedValue: "12")
      ],
      timestamp: sampleTime
    )
    let temporaryFailure = makeSPUSnapshot(
      status: .degraded, timestamp: sampleTime.addingTimeInterval(2))
    var stabilizer = SPUSnapshotStabilizer(graceInterval: 12)

    XCTAssertEqual(stabilizer.resolve(sample, now: sampleTime), sample)
    let resolved = stabilizer.resolve(
      temporaryFailure,
      now: sampleTime.addingTimeInterval(5)
    )

    XCTAssertEqual(resolved.status, .degraded)
    XCTAssertEqual(resolved.channels, sample.channels)
    XCTAssertEqual(resolved.timestamp, sampleTime)
    XCTAssertTrue(resolved.summary.contains("Recent live data"))
  }

  func testSPUStabilizerDropsExpiredCache() {
    let sampleTime = Date(timeIntervalSince1970: 1_000)
    let sample = makeSPUSnapshot(
      status: .available,
      channels: [
        SensorChannel(
          id: "ambient_intensity", label: "Ambient intensity", value: 12,
          formattedValue: "12")
      ],
      timestamp: sampleTime
    )
    let temporaryFailure = makeSPUSnapshot(
      status: .degraded, timestamp: sampleTime.addingTimeInterval(20))
    var stabilizer = SPUSnapshotStabilizer(graceInterval: 12)
    _ = stabilizer.resolve(sample, now: sampleTime)

    let resolved = stabilizer.resolve(
      temporaryFailure,
      now: sampleTime.addingTimeInterval(20)
    )

    XCTAssertEqual(resolved, temporaryFailure)
    XCTAssertTrue(resolved.channels.isEmpty)
  }

  private func makeSPUSnapshot(
    status: SensorStatus,
    channels: [SensorChannel] = [],
    timestamp: Date
  ) -> SensorSnapshot {
    SensorSnapshot(
      id: "motion.spu_live",
      name: "Motion & Ambient Light",
      category: .motion,
      summary: "Fixture",
      status: status,
      source: "Fixture",
      capability: .undocumented,
      channels: channels,
      timestamp: timestamp
    )
  }

  private func writeLittleEndian(_ value: UInt32, to bytes: inout [UInt8], at offset: Int) {
    bytes[offset] = UInt8(truncatingIfNeeded: value)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
    bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
  }

  private func assertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
  ) async {
    do {
      _ = try await expression()
      XCTFail("Expected expression to throw")
    } catch {
      errorHandler(error)
    }
  }
}

extension JSONDecoder {
  fileprivate static var withISO8601: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
