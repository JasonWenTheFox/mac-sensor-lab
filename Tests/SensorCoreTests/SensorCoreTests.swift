import Foundation
import XCTest

@testable import SensorCore

final class SensorCoreTests: XCTestCase {
  func testByteFormattingIsHumanReadable() {
    let value = SensorFormatting.bytes(1_073_741_824)
    XCTAssertTrue(value.contains("GB"))
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

  func testRegistryHasStableUniqueProviderIDs() {
    let ids = SensorProviderRegistry.providers().map(\.metadata.id)
    XCTAssertEqual(Set(ids).count, ids.count)
    XCTAssertGreaterThanOrEqual(ids.count, 10)
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
