import Foundation
import XCTest

@testable import SensorCore

final class SensorCoreTests: XCTestCase {
  func testByteFormattingIsHumanReadable() {
    let value = SensorFormatting.bytes(1_073_741_824)
    XCTAssertTrue(value.contains("GB"))
    XCTAssertTrue(SensorFormatting.bytesPerSecond(1_024).contains("/s"))
  }

  func testCSVScapesUnsafeCells() {
    XCTAssertEqual(SensorFormatting.csvCell("plain"), "plain")
    XCTAssertEqual(SensorFormatting.csvCell("a,b"), "\"a,b\"")
    XCTAssertEqual(SensorFormatting.csvCell("a\"b"), "\"a\"\"b\"")
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
    XCTAssertNil(AmbientLuxCalibration(rawReference: 0, luxReference: 100))
    XCTAssertNil(AmbientLuxCalibration(rawReference: 25, luxReference: -1))
  }

  func testRelativeAngleMeasurementPreservesDirection() throws {
    let opening = try XCTUnwrap(RelativeAngleMeasurement(current: 110, reference: 90))
    let closing = try XCTUnwrap(RelativeAngleMeasurement(current: 70, reference: 90))
    XCTAssertEqual(opening.delta, 20)
    XCTAssertEqual(closing.delta, -20)
    XCTAssertNil(RelativeAngleMeasurement(current: .nan, reference: 90))
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
      receivedBytes: 1_000,
      sentBytes: 2_000,
      receivedPackets: 10,
      sentPackets: 20,
      timestamp: 100
    )
    let current = NetworkCounterSample(
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
  }

  func testDiskIORateCalculatorUsesMonotonicDeltas() throws {
    let previous = DiskIOCounterSample(
      bytesRead: 1_000,
      bytesWritten: 2_000,
      readOperations: 10,
      writeOperations: 20,
      timestamp: 100
    )
    let current = DiskIOCounterSample(
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
      try XCTUnwrap(BatteryMeasurements.capacityRatio(nominal: 5_000, design: 6_250)),
      80,
      accuracy: 0.000_001
    )
    XCTAssertNil(BatteryMeasurements.capacityRatio(nominal: 5_000, design: 0))
    XCTAssertNil(BatteryMeasurements.capacityRatio(nominal: .nan, design: 6_250))
    XCTAssertEqual(BatteryMeasurements.validMinutes(90), 90)
    XCTAssertNil(BatteryMeasurements.validMinutes(65_535))
    XCTAssertNil(BatteryMeasurements.validMinutes(-1))
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
