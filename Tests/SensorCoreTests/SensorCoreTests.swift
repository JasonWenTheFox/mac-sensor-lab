import Foundation
import XCTest

@testable import SensorCore

final class SensorCoreTests: XCTestCase {
  func testLocalizationCatalogCoversStaticAppKeysAndGeneratedChineseStrings() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let catalogURL = projectRoot.appendingPathComponent("Resources/Localizable.xcstrings")
    let generatedURL = projectRoot.appendingPathComponent(
      "Resources/zh-Hans.lproj/Localizable.strings"
    )

    let catalogObject = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL))
    let catalog = try XCTUnwrap(catalogObject as? [String: Any])
    let catalogStrings = try XCTUnwrap(catalog["strings"] as? [String: Any])
    let catalogKeys = Set(catalogStrings.keys)

    let generatedObject = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: generatedURL),
      format: nil
    )
    let generatedStrings = try XCTUnwrap(generatedObject as? [String: String])
    XCTAssertEqual(Set(generatedStrings.keys), catalogKeys)
    XCTAssertEqual(generatedStrings["Overview"], "概览")
    XCTAssertEqual(generatedStrings["Every %lld seconds"], "每 %lld 秒")
    let formatExpression = try NSRegularExpression(pattern: "%(?:lld|@)")
    func formatTokens(in value: String) -> [String] {
      let range = NSRange(value.startIndex..<value.endIndex, in: value)
      return formatExpression.matches(in: value, range: range).compactMap { match in
        guard let tokenRange = Range(match.range, in: value) else { return nil }
        return String(value[tokenRange])
      }
    }
    for (key, value) in generatedStrings {
      XCTAssertEqual(
        formatTokens(in: value),
        formatTokens(in: key),
        "Localization changed format arguments for key: \(key)"
      )
    }

    let appSourceDirectory = projectRoot.appendingPathComponent(
      "Sources/MacSensorLab",
      isDirectory: true
    )
    let sourceURLs = try FileManager.default.contentsOfDirectory(
      at: appSourceDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }
    let source = try sourceURLs.map { try String(contentsOf: $0, encoding: .utf8) }
      .joined(separator: "\n")
    let expression = try NSRegularExpression(
      pattern: #"(?:L10n\.(?:text|format)|formatted)\(\s*\"([^\"]+)\""#
    )
    let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
    let usedKeys: Set<String> = Set(
      expression.matches(in: source, range: sourceRange).compactMap { match in
        guard let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
      }
    )
    XCTAssertTrue(
      usedKeys.isSubset(of: catalogKeys),
      "Missing localization keys: \(usedKeys.subtracting(catalogKeys).sorted())"
    )

    let sensorCoreSourceDirectory = projectRoot.appendingPathComponent(
      "Sources/SensorCore",
      isDirectory: true
    )
    let sensorCoreSourceURLs = try FileManager.default.contentsOfDirectory(
      at: sensorCoreSourceDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }
    let sensorCoreSource = try sensorCoreSourceURLs.map {
      try String(contentsOf: $0, encoding: .utf8)
    }.joined(separator: "\n")
    let displayExpression = try NSRegularExpression(
      pattern: #"(?:name|label):\s*\"([^\"]+)\""#
    )
    let sensorCoreRange = NSRange(
      sensorCoreSource.startIndex..<sensorCoreSource.endIndex,
      in: sensorCoreSource
    )
    let sensorDisplayKeys: Set<String> = Set(
      displayExpression.matches(in: sensorCoreSource, range: sensorCoreRange).compactMap { match in
        guard let range = Range(match.range(at: 1), in: sensorCoreSource) else { return nil }
        let key = String(sensorCoreSource[range])
        return key.contains("\\(") ? nil : key
      }
    )
    XCTAssertTrue(
      sensorDisplayKeys.isSubset(of: catalogKeys),
      "Missing sensor display translations: \(sensorDisplayKeys.subtracting(catalogKeys).sorted())"
    )
  }

  func testByteFormattingIsHumanReadable() {
    let value = SensorFormatting.bytes(1_073_741_824)
    XCTAssertTrue(value.contains("GB"))
    XCTAssertTrue(SensorFormatting.bytesPerSecond(1_024).contains("/s"))
    XCTAssertEqual(SensorFormatting.bytesPerSecond(Double(UInt64.max)), "Unavailable")
  }

  func testNumericSafetyRejectsOverflowingCountersAndConversions() {
    XCTAssertEqual(SensorNumericSafety.sum(40, 2), 42)
    XCTAssertNil(SensorNumericSafety.sum(.max, 1))
    XCTAssertEqual(SensorNumericSafety.product(21, 2), 42)
    XCTAssertNil(SensorNumericSafety.product(.max, 2))
    XCTAssertEqual(SensorNumericSafety.uint64(42.9), 42)
    XCTAssertNil(SensorNumericSafety.uint64(-1))
    XCTAssertNil(SensorNumericSafety.uint64(Double(UInt64.max)))
    XCTAssertEqual(SensorNumericSafety.boundedNonnegativeInteger(99, maximum: 4), 4)
    XCTAssertNil(SensorNumericSafety.boundedNonnegativeInteger(.infinity, maximum: 4))

    var counter = OptionalUInt64CounterAccumulator()
    counter.add(10)
    counter.add(20)
    XCTAssertEqual(counter.value, 30)
    counter.add(.max)
    XCTAssertNil(counter.value)
    XCTAssertTrue(counter.didOverflow)
    counter.add(1)
    XCTAssertNil(counter.value)
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
    XCTAssertEqual(report.schemaVersion, 2)
    XCTAssertEqual(report.providers.first?.providerID, "test.provider")
    XCTAssertEqual(report.providers.first?.channels.first?.channelID, "ambient_intensity")
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertFalse(text.contains("SENSITIVE_"))
    XCTAssertFalse(text.contains("123456"))
    XCTAssertFalse(text.contains("1000"))
  }

  func testSamplingHealthTracksTransitionsWithoutReadingsOrTimestamps() throws {
    func snapshot(_ status: SensorStatus) -> SensorSnapshot {
      SensorSnapshot(
        id: "environment.fixture",
        name: "SENSITIVE_NAME",
        category: .environment,
        summary: "SENSITIVE_SUMMARY",
        status: status,
        source: "SENSITIVE_SOURCE",
        capability: .undocumented,
        channels: [
          SensorChannel(
            id: "ambient_intensity",
            label: "SENSITIVE_LABEL",
            value: 987_654.321,
            formattedValue: "SENSITIVE_FORMATTED"
          )
        ],
        timestamp: Date(timeIntervalSince1970: 1_000)
      )
    }

    var tracker = SensorSamplingHealthTracker()
    _ = tracker.observe(snapshots: [snapshot(.available)], cycleDuration: 0.125)
    _ = tracker.observe(snapshots: [snapshot(.degraded)], cycleDuration: 0.250)
    let health = tracker.observe(snapshots: [snapshot(.available)], cycleDuration: 0.375)

    XCTAssertEqual(health.completedCycleCount, 3)
    XCTAssertEqual(health.lastCycleDurationMilliseconds, 375)
    XCTAssertEqual(health.totalStatusTransitionCount, 2)
    XCTAssertEqual(health.providers.first?.observationCount, 3)
    XCTAssertEqual(health.providers.first?.statusTransitionCount, 2)
    XCTAssertEqual(health.providers.first?.consecutiveIssueCount, 0)

    let data = try SensorDiagnosticsExportService.jsonData(
      [snapshot(.available)],
      applicationVersion: "test",
      generatedAt: Date(timeIntervalSince1970: 2_000),
      samplingHealth: health
    )
    let report = try JSONDecoder.withISO8601.decode(SensorDiagnosticsReport.self, from: data)
    XCTAssertEqual(report.sampling?.completedCycleCount, 3)
    XCTAssertEqual(report.sampling?.lastCycleDurationMilliseconds, 375)
    XCTAssertEqual(report.providers.first?.statusTransitionCount, 2)
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertFalse(text.contains("SENSITIVE_"))
    XCTAssertFalse(text.contains("987654"))
    XCTAssertFalse(text.contains("\"timestamp\""))
  }

  func testHistoryRetentionBoundsSeriesPointsAndRejectsMalformedSamples() {
    func snapshot(
      providerID: String,
      channelID: String = "cpu_utilization",
      value: Double,
      timestamp: TimeInterval
    ) -> SensorSnapshot {
      SensorSnapshot(
        id: providerID,
        name: "Fixture",
        category: .diagnostics,
        summary: "Fixture",
        status: .available,
        source: "Fixture",
        capability: .publicAPI,
        channels: [
          SensorChannel(
            id: channelID,
            label: "Value",
            value: value,
            formattedValue: "\(value)"
          )
        ],
        timestamp: Date(timeIntervalSinceReferenceDate: timestamp)
      )
    }

    var history: [String: [SensorHistoryPoint]] = [:]
    for index in 0..<4 {
      SensorHistoryRetention.append(
        snapshot(providerID: "provider.0", value: Double(index), timestamp: Double(index)),
        to: &history,
        maximumSeriesCount: 2,
        maximumPointsPerSeries: 2
      )
    }
    XCTAssertEqual(history["provider.0/cpu_utilization"]?.map(\.value), [2, 3])

    SensorHistoryRetention.append(
      snapshot(providerID: "provider.0", value: 99, timestamp: 3),
      to: &history,
      maximumSeriesCount: 2,
      maximumPointsPerSeries: 2
    )
    SensorHistoryRetention.append(
      snapshot(providerID: "provider.0", value: 98, timestamp: 2.5),
      to: &history,
      maximumSeriesCount: 2,
      maximumPointsPerSeries: 2
    )
    XCTAssertEqual(history["provider.0/cpu_utilization"]?.map(\.value), [2, 3])

    for providerIndex in 1...2 {
      SensorHistoryRetention.append(
        snapshot(
          providerID: "provider.\(providerIndex)",
          value: Double(providerIndex),
          timestamp: 4
        ),
        to: &history,
        maximumSeriesCount: 2,
        maximumPointsPerSeries: 2
      )
    }
    XCTAssertEqual(history.count, 2)
    XCTAssertNotNil(history["provider.1/cpu_utilization"])
    XCTAssertNil(history["provider.2/cpu_utilization"])

    var batteryHistory: [String: [SensorHistoryPoint]] = [:]
    SensorHistoryRetention.append(
      snapshot(providerID: "power.source", channelID: "battery_charge", value: 78, timestamp: 5),
      to: &batteryHistory,
      maximumSeriesCount: 2,
      maximumPointsPerSeries: 2
    )
    XCTAssertEqual(batteryHistory["power.source/battery_charge"]?.map(\.value), [78])

    var pairedHistory: [String: [SensorHistoryPoint]] = [:]
    for channelID in ["network_send_rate", "disk_write_rate", "gpu_hotspot"] {
      SensorHistoryRetention.append(
        snapshot(providerID: "rate.fixture", channelID: channelID, value: 42, timestamp: 6),
        to: &pairedHistory,
        maximumSeriesCount: 3,
        maximumPointsPerSeries: 2
      )
    }
    XCTAssertEqual(pairedHistory.count, 3)
    XCTAssertEqual(pairedHistory["rate.fixture/network_send_rate"]?.map(\.value), [42])
    XCTAssertEqual(pairedHistory["rate.fixture/disk_write_rate"]?.map(\.value), [42])
    XCTAssertEqual(pairedHistory["rate.fixture/gpu_hotspot"]?.map(\.value), [42])

    var malformedHistory: [String: [SensorHistoryPoint]] = [:]
    SensorHistoryRetention.append(
      snapshot(providerID: "ignored", channelID: "not_retained", value: 1, timestamp: 5),
      to: &malformedHistory,
      maximumSeriesCount: 2,
      maximumPointsPerSeries: 2
    )
    SensorHistoryRetention.append(
      snapshot(providerID: String(repeating: "a", count: 129), value: 1, timestamp: 5),
      to: &malformedHistory,
      maximumSeriesCount: 2,
      maximumPointsPerSeries: 2
    )
    SensorHistoryRetention.append(
      snapshot(providerID: "invalid.value", value: .infinity, timestamp: 5),
      to: &malformedHistory,
      maximumSeriesCount: 2,
      maximumPointsPerSeries: 2
    )
    SensorHistoryRetention.append(
      snapshot(providerID: "invalid.time", value: 1, timestamp: .infinity),
      to: &malformedHistory,
      maximumSeriesCount: 2,
      maximumPointsPerSeries: 2
    )
    XCTAssertTrue(malformedHistory.isEmpty)

    var clampedHistory: [String: [SensorHistoryPoint]] = [:]
    for providerIndex in 0...SensorHistoryRetention.maximumSeriesCount {
      SensorHistoryRetention.append(
        snapshot(providerID: "clamped.\(providerIndex)", value: 1, timestamp: 1),
        to: &clampedHistory,
        maximumSeriesCount: .max,
        maximumPointsPerSeries: .max
      )
    }
    XCTAssertEqual(clampedHistory.count, SensorHistoryRetention.maximumSeriesCount)

    for index in 2...(SensorHistoryRetention.maximumPointsPerSeries + 1) {
      SensorHistoryRetention.append(
        snapshot(providerID: "clamped.0", value: Double(index), timestamp: Double(index)),
        to: &clampedHistory,
        maximumSeriesCount: .max,
        maximumPointsPerSeries: .max
      )
    }
    let retainedPoints = clampedHistory["clamped.0/cpu_utilization"]
    XCTAssertEqual(retainedPoints?.count, SensorHistoryRetention.maximumPointsPerSeries)
    XCTAssertEqual(retainedPoints?.first?.value, 2)
    XCTAssertEqual(retainedPoints?.last?.value, 601)
  }

  func testSamplingHealthHandlesDuplicateIDsAndInvalidDurationsDefensively() {
    let first = SensorSnapshot(
      id: "test.provider",
      name: "Fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .degraded,
      source: "Fixture",
      capability: .publicAPI
    )
    let duplicate = SensorSnapshot(
      id: first.id,
      name: first.name,
      category: first.category,
      summary: first.summary,
      status: .available,
      source: first.source,
      capability: first.capability
    )

    var tracker = SensorSamplingHealthTracker()
    let firstCycle = tracker.observe(
      snapshots: [first, duplicate],
      cycleDuration: .infinity
    )
    XCTAssertNil(firstCycle.lastCycleDurationMilliseconds)
    XCTAssertEqual(firstCycle.providers.first?.observationCount, 1)
    XCTAssertEqual(firstCycle.providers.first?.consecutiveIssueCount, 1)

    let secondCycle = tracker.observe(snapshots: [duplicate], cycleDuration: -1)
    XCTAssertNil(secondCycle.lastCycleDurationMilliseconds)
    XCTAssertEqual(secondCycle.providers.first?.observationCount, 2)
    XCTAssertEqual(secondCycle.providers.first?.statusTransitionCount, 1)
    XCTAssertEqual(secondCycle.providers.first?.consecutiveIssueCount, 0)
    let unrepresentableDuration = tracker.observe(
      snapshots: [duplicate],
      cycleDuration: Double(UInt64.max) / 1_000
    )
    XCTAssertNil(unrepresentableDuration.lastCycleDurationMilliseconds)
  }

  func testSamplingHealthBoundsDynamicProviderStateAcrossCycles() {
    func snapshot(id: String) -> SensorSnapshot {
      SensorSnapshot(
        id: id,
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
    }

    var tracker = SensorSamplingHealthTracker(maximumTrackedProviders: 2)
    var health = SensorSamplingHealth.empty
    for index in 0..<10 {
      health = tracker.observe(
        snapshots: [snapshot(id: "dynamic.provider.\(index)")],
        cycleDuration: 0.001
      )
    }

    XCTAssertEqual(health.completedCycleCount, 10)
    XCTAssertEqual(
      health.providers.map(\.providerID),
      ["dynamic.provider.0", "dynamic.provider.1"]
    )
    XCTAssertEqual(health.providers.map(\.observationCount), [1, 1])

    health = tracker.observe(
      snapshots: [snapshot(id: "dynamic.provider.1")],
      cycleDuration: 0.001
    )
    XCTAssertEqual(health.providers.map(\.observationCount), [1, 2])

    var disabledTracker = SensorSamplingHealthTracker(maximumTrackedProviders: -1)
    let disabledHealth = disabledTracker.observe(
      snapshots: [snapshot(id: "ignored.provider")],
      cycleDuration: 0.001
    )
    XCTAssertTrue(disabledHealth.providers.isEmpty)

    let oversizedInput = (0...SensorContractAudit.maximumProviderCount).map { index in
      snapshot(id: "oversized.provider.\(index)")
    }
    var clampedTracker = SensorSamplingHealthTracker(maximumTrackedProviders: .max)
    let clampedHealth = clampedTracker.observe(
      snapshots: oversizedInput,
      cycleDuration: 0.001
    )
    XCTAssertEqual(clampedHealth.providers.count, SensorContractAudit.maximumProviderCount)
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

    let oversizedUnit = SensorSnapshot(
      id: "test.oversized",
      name: "Fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: [
        SensorChannel(
          id: "value",
          label: "Value",
          value: 1,
          formattedValue: "1",
          unit: String(repeating: "u", count: SensorContractAudit.maximumUnitByteCount + 1)
        )
      ]
    )
    XCTAssertThrowsError(
      try SensorDiagnosticsExportService.jsonData(
        [oversizedUnit],
        applicationVersion: "test"
      )
    ) { error in
      XCTAssertEqual(
        error as? SensorDiagnosticsExportError,
        .unsafeMetadata(code: .oversizedText, path: "snapshots[0].channels[0].unit")
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

  func testPrivateFileWriterAtomicallyReplacesWithOwnerOnlyPermissions() throws {
    func permissions(at url: URL) throws -> Int {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let destination = directory.appendingPathComponent("private.json")
    try Data("old".utf8).write(to: destination)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o666],
      ofItemAtPath: destination.path
    )

    let replacement = Data("replacement".utf8)
    try SensorPrivateFileWriter.write(replacement, to: destination)
    XCTAssertEqual(try Data(contentsOf: destination), replacement)
    XCTAssertEqual(try permissions(at: destination), 0o600)

    let directoryDestination = directory.appendingPathComponent("existing-directory")
    try FileManager.default.createDirectory(
      at: directoryDestination,
      withIntermediateDirectories: true
    )
    XCTAssertThrowsError(
      try SensorPrivateFileWriter.write(replacement, to: directoryDestination)
    )
    let remainingNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertFalse(remainingNames.contains { $0.hasPrefix(".mac-sensor-lab-export.") })

    let remoteURL = try XCTUnwrap(URL(string: "https://example.invalid/private.json"))
    XCTAssertThrowsError(try SensorPrivateFileWriter.write(replacement, to: remoteURL)) {
      XCTAssertEqual($0 as? SensorPrivateFileWriterError, .invalidDestination)
    }
  }

  func testCSVRecorderAppendsBatchesAndClosesCleanly() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("recording.csv")
    let recorder = try SensorCSVRecorder(destinationURL: destination)
    let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
    let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    XCTAssertEqual(permissions, 0o600)
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

  func testCSVRecorderRejectsMalformedSnapshotBeforeWriting() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("unsafe.csv")
    let recorder = try SensorCSVRecorder(destinationURL: destination)
    let malformed = SensorSnapshot(
      id: "test.unsafe",
      name: "Fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: [
        SensorChannel(id: "value", label: "Value", value: .nan, formattedValue: "nan")
      ]
    )

    await assertThrowsErrorAsync(try await recorder.append([malformed])) { error in
      XCTAssertEqual(
        error as? SensorCSVRecorderError,
        .unsafeSnapshot(code: .nonFiniteValue, path: "snapshots[0].channels[0].value")
      )
    }
    let progress = try await recorder.finish()
    XCTAssertEqual(progress.rowCount, 0)
    XCTAssertEqual(
      try Data(contentsOf: destination),
      Data(SensorCSVStreamEncoder.header.utf8)
    )
  }

  func testCSVRecorderBoundsProviderDeduplicationStateAcrossBatches() async throws {
    func snapshot(id: String, timestamp: TimeInterval) -> SensorSnapshot {
      SensorSnapshot(
        id: id,
        name: "Fixture",
        category: .diagnostics,
        summary: "Fixture",
        status: .unavailable,
        source: "Fixture",
        capability: .publicAPI,
        timestamp: Date(timeIntervalSinceReferenceDate: timestamp)
      )
    }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("bounded-markers.csv")
    let recorder = try SensorCSVRecorder(destinationURL: destination)
    let initialBatch = (0..<SensorCSVRecorder.maximumTrackedProviderCount).map { index in
      snapshot(id: "fixture.provider_\(index)", timestamp: 1)
    }

    let initialProgress = try await recorder.appendNewSnapshots(initialBatch)
    XCTAssertEqual(initialProgress.rowCount, SensorCSVRecorder.maximumTrackedProviderCount)

    let overflowSnapshot = snapshot(id: "fixture.provider_overflow", timestamp: 1)
    await assertThrowsErrorAsync(
      try await recorder.appendNewSnapshots([overflowSnapshot])
    ) { error in
      XCTAssertEqual(
        error as? SensorCSVRecorderError,
        .trackedProviderLimitReached(limit: SensorCSVRecorder.maximumTrackedProviderCount)
      )
    }

    let existingProviderUpdate = snapshot(id: "fixture.provider_0", timestamp: 2)
    let finalProgress = try await recorder.appendNewSnapshots([existingProviderUpdate])
    XCTAssertEqual(
      finalProgress.rowCount,
      SensorCSVRecorder.maximumTrackedProviderCount + 1
    )
    _ = try await recorder.finish()
  }

  func testCSVRecorderPreflightsTheWholeBatchBeforeWritingRows() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("preflight.csv")
    let snapshot = makeSPUSnapshot(
      status: .available,
      channels: [
        SensorChannel(id: "one", label: "One", value: 1, formattedValue: "1"),
        SensorChannel(id: "two", label: "Two", value: 2, formattedValue: "2"),
      ],
      timestamp: Date(timeIntervalSince1970: 1_000)
    )
    let batchByteCount = SensorCSVStreamEncoder.data(
      for: [snapshot], includeHeader: false
    ).count
    let limit = SensorCSVStreamEncoder.header.utf8.count + batchByteCount - 1
    let recorder = try SensorCSVRecorder(destinationURL: destination, byteLimit: limit)

    await assertThrowsErrorAsync(try await recorder.append([snapshot])) { error in
      XCTAssertEqual(error as? SensorCSVRecorderError, .sizeLimitReached(limit: limit))
    }
    let progress = try await recorder.finish()
    XCTAssertEqual(progress.rowCount, 0)
    XCTAssertEqual(progress.byteCount, SensorCSVStreamEncoder.header.utf8.count)
    XCTAssertEqual(
      try Data(contentsOf: destination),
      Data(SensorCSVStreamEncoder.header.utf8)
    )
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

  func testCSVRecorderFinishRefreshesFinalFileSizeAfterExternalAppend() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("finish-recount.csv")
    let recorder = try SensorCSVRecorder(destinationURL: destination)
    let externalData = Data("external-final-append\n".utf8)
    let externalHandle = try FileHandle(forWritingTo: destination)
    try externalHandle.seekToEnd()
    try externalHandle.write(contentsOf: externalData)
    try externalHandle.synchronize()
    try externalHandle.close()

    let progress = try await recorder.finish()
    XCTAssertEqual(progress.rowCount, 0)
    XCTAssertEqual(progress.byteCount, try Data(contentsOf: destination).count)
    XCTAssertEqual(
      progress.byteCount,
      SensorCSVStreamEncoder.header.utf8.count + externalData.count
    )
    await assertThrowsErrorAsync(try await recorder.finish()) { error in
      XCTAssertEqual(error as? SensorCSVRecorderError, .alreadyClosed)
    }
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
      status: .unavailable,
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

  func testMotionVariationStatisticsAreFiniteAndFactLimited() throws {
    let statistics = try XCTUnwrap(
      MotionVariationStatistics(values: [.nan, 0.9, 1.0, 1.1, .infinity]))
    XCTAssertEqual(statistics.sampleCount, 3)
    XCTAssertEqual(statistics.mean, 1, accuracy: 0.000_001)
    XCTAssertEqual(statistics.rmsDeviation, sqrt(0.02 / 3), accuracy: 0.000_001)
    XCTAssertEqual(statistics.peakToPeak, 0.2, accuracy: 0.000_001)
    XCTAssertNil(MotionVariationStatistics(values: [.nan, 1]))
    XCTAssertNil(
      MotionVariationStatistics(values: [-.greatestFiniteMagnitude, .greatestFiniteMagnitude]))
  }

  func testAmbientLuxCalibrationIsExplicitAndValidated() throws {
    let calibration = try XCTUnwrap(
      AmbientLuxCalibration(
        rawReference: 25,
        luxReference: 100,
        capturedAt: Date(timeIntervalSince1970: 1_000)
      ))
    XCTAssertEqual(calibration.scale, 4)
    XCTAssertEqual(calibration.pointCount, 1)
    XCTAssertEqual(calibration.rootMeanSquareError, 0)
    XCTAssertEqual(try XCTUnwrap(calibration.estimatedLux(for: 12.5)), 50)
    let channel = try XCTUnwrap(calibration.estimatedChannel(for: 12.5))
    XCTAssertEqual(channel.id, "ambient_estimated_lux")
    XCTAssertEqual(channel.value, 50)
    XCTAssertEqual(channel.unit, "lux")
    XCTAssertEqual(channel.kind, .estimated)
    XCTAssertNil(calibration.estimatedLux(for: .nan))
    let encoded = try JSONEncoder().encode(calibration)
    XCTAssertEqual(try JSONDecoder().decode(AmbientLuxCalibration.self, from: encoded), calibration)
    let legacy = Data(
      "{\"rawReference\":25,\"luxReference\":100,\"capturedAt\":0}".utf8
    )
    XCTAssertEqual(
      try JSONDecoder().decode(AmbientLuxCalibration.self, from: legacy).pointCount,
      1
    )
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

  func testAmbientLuxCalibrationFitsBoundedMonotonicPointsAndSupportsUndo() throws {
    let first = try XCTUnwrap(
      AmbientLuxCalibration(
        rawReference: 10,
        luxReference: 105,
        capturedAt: Date(timeIntervalSince1970: 1)
      ))
    let twoPoints = try XCTUnwrap(
      first.addingPoint(
        rawReference: 20,
        luxReference: 205,
        capturedAt: Date(timeIntervalSince1970: 2)
      ))
    let calibration = try XCTUnwrap(
      twoPoints.addingPoint(
        rawReference: 30,
        luxReference: 305,
        capturedAt: Date(timeIntervalSince1970: 3)
      ))

    XCTAssertEqual(calibration.pointCount, 3)
    XCTAssertEqual(calibration.scale, 10, accuracy: 0.000_001)
    XCTAssertEqual(calibration.rootMeanSquareError, 0, accuracy: 0.000_001)
    XCTAssertEqual(try XCTUnwrap(calibration.estimatedLux(for: 15)), 155, accuracy: 0.000_001)
    XCTAssertEqual(
      try XCTUnwrap(calibration.estimatedChannel(for: 15)).kind,
      .estimated
    )
    XCTAssertEqual(try XCTUnwrap(calibration.removingLastPoint()).pointCount, 2)

    let replaced = try XCTUnwrap(
      calibration.addingPoint(
        rawReference: 20,
        luxReference: 210,
        capturedAt: Date(timeIntervalSince1970: 4)
      ))
    XCTAssertEqual(replaced.pointCount, 3)
    XCTAssertEqual(replaced.rawReference, 20)
    XCTAssertEqual(replaced.luxReference, 210)
    XCTAssertGreaterThan(replaced.rootMeanSquareError, 0)
    XCTAssertNil(calibration.addingPoint(rawReference: 40, luxReference: 100))

    var bounded = first
    for value in 2...AmbientLuxCalibration.maximumPointCount {
      bounded = try XCTUnwrap(
        bounded.addingPoint(rawReference: Double(value) * 10, luxReference: Double(value) * 100)
      )
    }
    XCTAssertEqual(bounded.pointCount, AmbientLuxCalibration.maximumPointCount)
    XCTAssertNil(bounded.addingPoint(rawReference: 90, luxReference: 900))
  }

  func testAmbientLuxCalibrationRejectsDuplicateAndUnsupportedPointPayloads() throws {
    let point = try XCTUnwrap(
      AmbientLuxCalibrationPoint(rawReference: 10, luxReference: 100)
    )
    XCTAssertNil(AmbientLuxCalibration(points: [point, point]))
    XCTAssertNil(
      AmbientLuxCalibration(points: [
        point,
        try XCTUnwrap(AmbientLuxCalibrationPoint(rawReference: 20, luxReference: 50)),
      ]))
    XCTAssertNil(AmbientLuxCalibrationPoint(rawReference: .nan, luxReference: 100))

    let missingSchema = Data(
      "{\"points\":[]}".utf8
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(AmbientLuxCalibration.self, from: missingSchema)
    )
    let unsupportedSchema = Data(
      "{\"schemaVersion\":3,\"points\":[]}".utf8
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(AmbientLuxCalibration.self, from: unsupportedSchema)
    )
  }

  func testAmbientCalibrationFileRoundTripsAndBoundsInput() throws {
    let first = try XCTUnwrap(
      AmbientLuxCalibration(
        rawReference: 25,
        luxReference: 100,
        capturedAt: Date(timeIntervalSince1970: 1_000)
      ))
    let calibration = try XCTUnwrap(
      first.addingPoint(
        rawReference: 50,
        luxReference: 220,
        capturedAt: Date(timeIntervalSince1970: 2_000)
      ))
    let data = try AmbientLuxCalibrationFileService.data(for: calibration)
    XCTAssertLessThan(data.count, AmbientLuxCalibrationFileService.maximumByteCount)
    XCTAssertEqual(
      try AmbientLuxCalibrationFileService.calibration(from: data),
      calibration
    )
    let legacyData = Data(
      "{\"rawReference\":25,\"luxReference\":100,\"capturedAt\":\"1970-01-01T00:16:40Z\"}"
        .utf8
    )
    XCTAssertEqual(
      try AmbientLuxCalibrationFileService.calibration(from: legacyData).pointCount,
      1
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

  func testBatteryDischargeEstimateUsesAConservativeObservedWindow() throws {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let points = (0..<6).map { index in
      SensorHistoryPoint(
        timestamp: start.addingTimeInterval(Double(index) * 60),
        value: 80 - Double(index) * 0.2
      )
    }

    let estimate = try XCTUnwrap(BatteryDischargeEstimate(points: points))

    XCTAssertEqual(estimate.sampleCount, 6)
    XCTAssertEqual(estimate.duration, 300, accuracy: 0.001)
    XCTAssertEqual(estimate.chargeDrop, 1, accuracy: 0.001)
    XCTAssertEqual(estimate.percentPerHour, 12, accuracy: 0.001)
    XCTAssertEqual(estimate.estimatedHoursToEmpty, 79 / 12, accuracy: 0.001)

    let discharging = PublicPowerSourceProvider().snapshot(
      reading: PublicPowerSourceReading(
        source: .battery,
        batteryWarning: PublicBatteryWarning.none,
        currentCapacity: 79,
        maximumCapacity: 100,
        isCharging: false,
        timeToEmptyMinutes: nil,
        timeToFullMinutes: nil,
        systemTimeRemainingSeconds: nil
      )
    )
    XCTAssertTrue(BatteryDischargeEstimate.isEligible(snapshot: discharging))
    let charging = PublicPowerSourceProvider().snapshot(
      reading: PublicPowerSourceReading(
        source: .battery,
        batteryWarning: PublicBatteryWarning.none,
        currentCapacity: 79,
        maximumCapacity: 100,
        isCharging: true,
        timeToEmptyMinutes: nil,
        timeToFullMinutes: nil,
        systemTimeRemainingSeconds: nil
      )
    )
    XCTAssertFalse(BatteryDischargeEstimate.isEligible(snapshot: charging))
  }

  func testBatteryDischargeEstimateRejectsWeakMalformedOrMixedWindows() {
    let start = Date(timeIntervalSinceReferenceDate: 2_000)
    func point(_ minute: Double, _ charge: Double) -> SensorHistoryPoint {
      SensorHistoryPoint(timestamp: start.addingTimeInterval(minute * 60), value: charge)
    }

    XCTAssertNil(
      BatteryDischargeEstimate(points: [point(0, 80), point(1, 79.8), point(2, 79.6)])
    )
    XCTAssertNil(
      BatteryDischargeEstimate(
        points: [point(0, 80), point(2, 79.9), point(4, 79.8), point(5, 79.7)]
      )
    )
    XCTAssertNil(
      BatteryDischargeEstimate(
        points: [point(0, 80), point(2, 80.2), point(4, 80.4), point(6, 80.6)]
      )
    )
    XCTAssertNil(
      BatteryDischargeEstimate(
        points: [point(0, 80), point(2, 79.8), point(1, 79.6), point(6, 79.4)]
      )
    )
    XCTAssertNil(
      BatteryDischargeEstimate(
        points: [point(0, 80), point(2, 79.8), point(4, .nan), point(6, 79.4)]
      )
    )

    let mixed = [
      point(0, 70), point(2, 72), point(4, 72), point(6, 71.8), point(8, 71.6),
      point(10, 71.4), point(12, 71.2),
    ]
    let estimate = BatteryDischargeEstimate(points: mixed)
    XCTAssertEqual(estimate?.sampleCount, 6)
    XCTAssertEqual(estimate?.chargeDrop ?? .nan, 0.8, accuracy: 0.001)
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
    let overflowing = CPUTickSample(user: .max, system: 1, idle: 0, nice: 0)
    XCTAssertNil(CPUUsageCalculator.percentage(previous: previous, current: overflowing))
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
    let localizedText = [
      "Disk Activity": "磁盘活动",
      "Write rate": "写入速率",
    ]
    let localizedProviderMatch = try XCTUnwrap(
      SensorSnapshotSearch.filter(
        [snapshot],
        query: "磁盘活动",
        localizedDisplayText: { localizedText[$0] ?? $0 }
      ).first
    )
    XCTAssertEqual(localizedProviderMatch.channels.count, 2)
    let localizedChannelMatch = try XCTUnwrap(
      SensorSnapshotSearch.filter(
        [snapshot],
        query: "写入速率",
        localizedDisplayText: { localizedText[$0] ?? $0 }
      ).first
    )
    XCTAssertEqual(localizedChannelMatch.channels.map(\.id), ["disk_write_rate"])
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
    XCTAssertEqual(BatteryMeasurements.capacity(5_000), 5_000)
    XCTAssertNil(BatteryMeasurements.capacity(-1))
    XCTAssertNil(BatteryMeasurements.capacity(.infinity))
  }

  func testPublicPowerSourceSnapshotKeepsSupportedFactsSeparate() throws {
    let snapshot = PublicPowerSourceProvider().snapshot(
      reading: PublicPowerSourceReading(
        source: .battery,
        batteryWarning: PublicBatteryWarning.none,
        currentCapacity: 78,
        maximumCapacity: 100,
        isCharging: false,
        timeToEmptyMinutes: 285,
        timeToFullMinutes: 45,
        systemTimeRemainingSeconds: 16_800
      )
    )
    let channels = Dictionary(uniqueKeysWithValues: snapshot.channels.map { ($0.id, $0) })

    XCTAssertEqual(snapshot.status, .available)
    XCTAssertEqual(snapshot.capability, .publicAPI)
    XCTAssertEqual(channels["active_source"]?.formattedValue, "Battery")
    XCTAssertEqual(try XCTUnwrap(channels["battery_charge"]?.value), 78, accuracy: 0.001)
    XCTAssertEqual(channels["battery_charging"]?.formattedValue, "No")
    XCTAssertEqual(channels["battery_warning"]?.formattedValue, "No warning")
    XCTAssertEqual(
      try XCTUnwrap(channels["system_time_remaining"]?.value), 280, accuracy: 0.001)
    XCTAssertEqual(
      try XCTUnwrap(channels["battery_time_to_empty"]?.value), 285, accuracy: 0.001)
    XCTAssertNil(channels["battery_time_to_full"])
    XCTAssertTrue(snapshot.notes.joined().contains("serial numbers"))
    XCTAssertTrue(SensorContractAudit.issues(for: [snapshot]).isEmpty)
  }

  func testPublicPowerSourceSnapshotOmitsSentinelsAndInvalidValues() {
    let snapshot = PublicPowerSourceProvider().snapshot(
      reading: PublicPowerSourceReading(
        source: nil,
        batteryWarning: nil,
        currentCapacity: .nan,
        maximumCapacity: 0,
        isCharging: nil,
        timeToEmptyMinutes: -1,
        timeToFullMinutes: .infinity,
        systemTimeRemainingSeconds: -2
      )
    )

    XCTAssertEqual(snapshot.status, .degraded)
    XCTAssertTrue(snapshot.channels.isEmpty)
    XCTAssertTrue(SensorContractAudit.issues(for: [snapshot]).isEmpty)
    XCTAssertNil(PublicPowerSourceKind(systemValue: "Unexpected external value"))
    XCTAssertNil(PublicPowerSourceMeasurements.validSystemMinutes(seconds: .infinity))
    XCTAssertNil(PublicPowerSourceMeasurements.chargePercentage(current: 200, maximum: 250))
  }

  func testPublicPowerSourceShowsChargeTimeOnlyWhileCharging() throws {
    let snapshot = PublicPowerSourceProvider().snapshot(
      reading: PublicPowerSourceReading(
        source: .ac,
        batteryWarning: PublicBatteryWarning.none,
        currentCapacity: 50,
        maximumCapacity: 100,
        isCharging: true,
        timeToEmptyMinutes: 120,
        timeToFullMinutes: 45,
        systemTimeRemainingSeconds: -2
      )
    )
    let channels = Dictionary(uniqueKeysWithValues: snapshot.channels.map { ($0.id, $0) })

    XCTAssertEqual(channels["active_source"]?.formattedValue, "AC power")
    XCTAssertEqual(try XCTUnwrap(channels["battery_time_to_full"]?.value), 45, accuracy: 0.001)
    XCTAssertNil(channels["battery_time_to_empty"])
    XCTAssertNil(channels["system_time_remaining"])
  }

  func testPublicBatteryWarningMapsOnlyDocumentedSystemLevels() {
    XCTAssertEqual(
      PublicBatteryWarning(systemValue: kIOPSLowBatteryWarningNone),
      PublicBatteryWarning.none
    )
    XCTAssertEqual(
      PublicBatteryWarning(systemValue: kIOPSLowBatteryWarningEarly),
      .early
    )
    XCTAssertEqual(
      PublicBatteryWarning(systemValue: kIOPSLowBatteryWarningFinal),
      .final
    )
    XCTAssertNil(PublicBatteryWarning(systemValue: IOPSLowBatteryWarningLevel(rawValue: 99)))
  }

  func testDisplaySnapshotSeparatesPixelsPointsAndDerivedScale() throws {
    let snapshot = DisplayProvider().snapshot(
      displayCount: 2,
      reading: PublicDisplayModeReading(
        pixelWidth: 3_024,
        pixelHeight: 1_964,
        pointWidth: 1_512,
        pointHeight: 982,
        refreshRate: 120
      )
    )
    let channels = Dictionary(uniqueKeysWithValues: snapshot.channels.map { ($0.id, $0) })

    XCTAssertEqual(snapshot.status, .available)
    XCTAssertEqual(snapshot.summary, "3024 × 1964 px • 2 active")
    XCTAssertEqual(channels["main_resolution"]?.formattedValue, "3024 × 1964")
    XCTAssertEqual(channels["main_resolution"]?.unit, "pixels")
    XCTAssertEqual(channels["main_logical_resolution"]?.formattedValue, "1512 × 982")
    XCTAssertEqual(channels["main_logical_resolution"]?.unit, "points")
    XCTAssertEqual(try XCTUnwrap(channels["backing_scale"]?.value), 2, accuracy: 0.001)
    XCTAssertEqual(channels["backing_scale"]?.kind, .derived)
    XCTAssertEqual(try XCTUnwrap(channels["refresh_rate"]?.value), 120, accuracy: 0.001)
  }

  func testDisplayMeasurementsOmitInvalidOrInconsistentModeFacts() {
    let snapshot = DisplayProvider().snapshot(
      displayCount: 1,
      reading: PublicDisplayModeReading(
        pixelWidth: 0,
        pixelHeight: 1_964,
        pointWidth: 1_512,
        pointHeight: 900,
        refreshRate: .nan
      )
    )
    let channelIDs = Set(snapshot.channels.map(\.id))

    XCTAssertEqual(snapshot.summary, "1 active displays")
    XCTAssertFalse(channelIDs.contains("main_resolution"))
    XCTAssertTrue(channelIDs.contains("main_logical_resolution"))
    XCTAssertFalse(channelIDs.contains("backing_scale"))
    XCTAssertFalse(channelIDs.contains("refresh_rate"))
    XCTAssertNil(PublicDisplayMeasurements.validDimension(100_001))
    XCTAssertNil(
      PublicDisplayMeasurements.backingScale(
        pixelWidth: 3_024,
        pixelHeight: 1_964,
        pointWidth: 1_512,
        pointHeight: 900
      )
    )
  }

  func testStorageSnapshotKeepsPublicCapacitySemanticsSeparate() throws {
    let snapshot = StorageProvider().snapshot(
      reading: PublicStorageCapacityReading(
        total: 1_000,
        available: 300,
        availableForImportantUsage: 450,
        availableForOpportunisticUsage: 200
      )
    )
    let channels = Dictionary(uniqueKeysWithValues: snapshot.channels.map { ($0.id, $0) })

    XCTAssertEqual(snapshot.status, .available)
    XCTAssertEqual(try XCTUnwrap(channels["total"]?.value), 1_000, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(channels["available"]?.value), 300, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(channels["available_important"]?.value), 450, accuracy: 0.001)
    XCTAssertEqual(
      try XCTUnwrap(channels["available_opportunistic"]?.value),
      200,
      accuracy: 0.001
    )
    XCTAssertEqual(try XCTUnwrap(channels["used"]?.value), 700, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(channels["used_percent"]?.value), 70, accuracy: 0.001)
    XCTAssertEqual(channels["used"]?.kind, .derived)
  }

  func testStorageMeasurementsRejectInvalidOrImpossibleCapacities() {
    XCTAssertNil(PublicStorageCapacityMeasurements.bytes(Int(-1)))
    XCTAssertNil(PublicStorageCapacityMeasurements.bytes(Int64(-1)))
    XCTAssertEqual(PublicStorageCapacityMeasurements.bytes(Int(42)), 42)
    XCTAssertEqual(PublicStorageCapacityMeasurements.bytes(Int64(42)), 42)
    XCTAssertNil(PublicStorageCapacityMeasurements.boundedAvailable(1_001, total: 1_000))
    XCTAssertNil(PublicStorageCapacityMeasurements.used(total: 0, available: 0))
    XCTAssertNil(PublicStorageCapacityMeasurements.usedPercentage(total: 1_000, available: 1_001))

    let degraded = StorageProvider().snapshot(
      reading: PublicStorageCapacityReading(
        total: 1_000,
        available: 1_001,
        availableForImportantUsage: 900,
        availableForOpportunisticUsage: 1_001
      )
    )
    let channelIDs = Set(degraded.channels.map(\.id))
    XCTAssertEqual(degraded.status, .degraded)
    XCTAssertEqual(channelIDs, ["total", "available_important"])
    XCTAssertFalse(degraded.notes.joined().contains("/"))

    let unavailable = StorageProvider().snapshot(
      reading: PublicStorageCapacityReading(
        total: nil,
        available: 1,
        availableForImportantUsage: nil,
        availableForOpportunisticUsage: nil
      )
    )
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertTrue(unavailable.channels.isEmpty)
    XCTAssertFalse(unavailable.notes.joined().contains("/"))
  }

  func testThermalProviderKeepsStateAndOrdinalEncodingSeparate() throws {
    XCTAssertEqual(SystemThermalPressure(systemState: .nominal), .nominal)
    XCTAssertEqual(SystemThermalPressure(systemState: .fair), .fair)
    XCTAssertEqual(SystemThermalPressure(systemState: .serious), .serious)
    XCTAssertEqual(SystemThermalPressure(systemState: .critical), .critical)

    let snapshot = ThermalProvider().snapshot(
      reading: PublicThermalReading(pressure: .serious, lowPowerModeEnabled: true)
    )
    let channels = Dictionary(uniqueKeysWithValues: snapshot.channels.map { ($0.id, $0) })

    XCTAssertEqual(channels["thermal_state"]?.formattedValue, "Serious")
    XCTAssertNil(channels["thermal_state"]?.value)
    XCTAssertEqual(try XCTUnwrap(channels["thermal_pressure_level"]?.value), 2, accuracy: 0.001)
    XCTAssertEqual(channels["thermal_pressure_level"]?.formattedValue, "Serious")
    XCTAssertEqual(channels["thermal_pressure_level"]?.kind, .derived)
    XCTAssertEqual(channels["low_power_mode"]?.value, 1)
  }

  func testThermalPressureTrendRejectsNonOrdinalOrMalformedHistory() throws {
    let start = Date(timeIntervalSinceReferenceDate: 3_000)
    func point(_ offset: Double, _ value: Double) -> SensorHistoryPoint {
      SensorHistoryPoint(timestamp: start.addingTimeInterval(offset), value: value)
    }
    let trend = try XCTUnwrap(
      ThermalPressureTrend(
        points: [point(0, 0), point(1, 0), point(2, 1), point(3, 2), point(4, 1)]
      )
    )

    XCTAssertEqual(trend.sampleCount, 5)
    XCTAssertEqual(trend.latest, .fair)
    XCTAssertEqual(trend.highest, .serious)
    XCTAssertEqual(trend.transitionCount, 3)
    XCTAssertNil(ThermalPressureTrend(points: [point(0, 0.5)]))
    XCTAssertNil(ThermalPressureTrend(points: [point(0, 4)]))
    XCTAssertNil(ThermalPressureTrend(points: [point(1, 0), point(0, 1)]))
    XCTAssertNil(ThermalPressureTrend(points: [point(0, .nan)]))
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

  func testStatusCountsKeepPermissionUnavailableAndErrorsSeparate() {
    let statuses: [SensorStatus] = [
      .loading, .available, .available, .degraded, .permissionRequired, .unavailable, .error,
    ]
    let snapshots = statuses.enumerated().map { index, status in
      SensorSnapshot(
        id: "test.status_\(index)",
        name: "Fixture \(index)",
        category: .diagnostics,
        summary: "Fixture",
        status: status,
        source: "Fixture",
        capability: .publicAPI
      )
    }
    let counts = SensorStatusCounts(snapshots: snapshots)

    XCTAssertEqual(counts.loading, 1)
    XCTAssertEqual(counts.available, 2)
    XCTAssertEqual(counts.degraded, 1)
    XCTAssertEqual(counts.permissionRequired, 1)
    XCTAssertEqual(counts.unavailable, 1)
    XCTAssertEqual(counts.error, 1)
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

  func testContractAuditRejectsNonFiniteOrOverflowingFutureTolerance() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)
    let future = SensorSnapshot(
      id: "test.future",
      name: "Fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .unavailable,
      source: "Fixture",
      capability: .publicAPI,
      timestamp: now.addingTimeInterval(1)
    )

    XCTAssertFalse(
      SensorContractAudit.issues(for: [future], now: now, futureTolerance: 2).contains {
        $0.code == .futureTimestamp
      }
    )
    for invalidTolerance in [Double.nan, .infinity, -1] {
      XCTAssertTrue(
        SensorContractAudit.issues(
          for: [future],
          now: now,
          futureTolerance: invalidTolerance
        ).contains { $0.code == .futureTimestamp }
      )
    }

    let largeNow = Date(
      timeIntervalSinceReferenceDate: Double.greatestFiniteMagnitude / 2
    )
    let largeFuture = SensorSnapshot(
      id: future.id,
      name: future.name,
      category: future.category,
      summary: future.summary,
      status: future.status,
      source: future.source,
      capability: future.capability,
      timestamp: Date(
        timeIntervalSinceReferenceDate: Double.greatestFiniteMagnitude * 0.75
      )
    )
    XCTAssertTrue(
      SensorContractAudit.issues(
        for: [largeFuture],
        now: largeNow,
        futureTolerance: .greatestFiniteMagnitude
      ).contains { $0.code == .futureTimestamp }
    )
  }

  func testContractAuditRejectsBlankInconsistentAndUnboundedPayloads() {
    var tooManyChannels: [SensorChannel] = []
    for index in 0...SensorContractAudit.maximumChannelsPerProvider {
      let label = index == 0 ? " " : "Channel \(index)"
      let formattedValue =
        index == 1
        ? String(repeating: "x", count: SensorContractAudit.maximumDisplayTextByteCount + 1)
        : "\(index)"
      let unit: String? =
        index == 2
        ? String(repeating: "u", count: SensorContractAudit.maximumUnitByteCount + 1)
        : nil
      tooManyChannels.append(
        SensorChannel(
          id: "channel_\(index)",
          label: label,
          value: Double(index),
          formattedValue: formattedValue,
          unit: unit,
          note: index == 3 ? "" : nil
        ))
    }
    let malformed = SensorSnapshot(
      id: String(repeating: "a", count: SensorContractAudit.maximumIdentifierByteCount + 1),
      name: " ",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: tooManyChannels,
      notes: ["Repeated", "Repeated"]
    )
    let loading = SensorSnapshot(
      id: "test.loading",
      name: "Loading fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .loading,
      source: "Fixture",
      capability: .publicAPI
    )
    let emptyAvailable = SensorSnapshot(
      id: "test.empty",
      name: "Empty fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI
    )
    let tooManyNotes = SensorSnapshot(
      id: "test.notes",
      name: "Notes fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .degraded,
      source: "Fixture",
      capability: .publicAPI,
      notes: (0...SensorContractAudit.maximumNotesPerProvider).map { "Note \($0)" }
    )

    let codes: Set<SensorContractIssue.Code> = Set(
      SensorContractAudit.issues(for: [malformed, loading, emptyAvailable, tooManyNotes]).map(
        \.code)
    )
    XCTAssertTrue(codes.contains(.invalidStableIdentifier))
    XCTAssertTrue(codes.contains(.emptyText))
    XCTAssertTrue(codes.contains(.oversizedText))
    XCTAssertTrue(codes.contains(.duplicateNote))
    XCTAssertTrue(codes.contains(.tooManyChannels))
    XCTAssertTrue(codes.contains(.tooManyNotes))
    XCTAssertTrue(codes.contains(.unexpectedLoadingStatus))
    XCTAssertTrue(codes.contains(.availableWithoutChannels))

    let tooManyProviders = (0...SensorContractAudit.maximumProviderCount).map { index in
      SensorSnapshot(
        id: "test.provider_\(index)",
        name: "Provider \(index)",
        category: .diagnostics,
        summary: "Fixture",
        status: .unavailable,
        source: "Fixture",
        capability: .publicAPI
      )
    }
    XCTAssertTrue(
      SensorContractAudit.issues(for: tooManyProviders).contains {
        $0.code == .tooManyProviders
      })
  }

  func testContractAuditDoesNotEchoOrDeduplicateOversizedStrings() {
    let tailMarker = "PRIVATE_TAIL_MARKER"
    let oversizedIdentifier = String(repeating: "a", count: 1_000_000) + tailMarker
    let oversizedText = String(repeating: " ", count: 1_000_000) + tailMarker
    let malformed = SensorSnapshot(
      id: oversizedIdentifier,
      name: oversizedText,
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: [
        SensorChannel(
          id: oversizedIdentifier,
          label: oversizedText,
          value: 1,
          formattedValue: oversizedText,
          unit: oversizedText,
          note: oversizedText
        )
      ],
      notes: [oversizedText, oversizedText]
    )

    let issues = SensorContractAudit.issues(
      providers: [],
      snapshots: [malformed]
    )
    let codes = Set(issues.map(\.code))
    XCTAssertTrue(codes.contains(.invalidStableIdentifier))
    XCTAssertTrue(codes.contains(.oversizedText))
    XCTAssertFalse(codes.contains(.duplicateProviderIdentifier))
    XCTAssertFalse(codes.contains(.duplicateChannelIdentifier))
    XCTAssertFalse(codes.contains(.duplicateNote))
    XCTAssertFalse(codes.contains(.unexpectedProviderIdentifier))

    let issueText = issues.map(\.description).joined(separator: "\n")
    XCTAssertFalse(issueText.contains(tailMarker))
    XCTAssertLessThan(issueText.utf8.count, 16_384)
  }

  func testContractAuditCapsTotalIssueOutputAndScanning() {
    let invalidChannels = (0..<SensorContractAudit.maximumChannelsPerProvider).map { index in
      SensorChannel(
        id: "Bad ID \(index)",
        label: " ",
        value: .nan,
        formattedValue: " ",
        unit: " ",
        note: " "
      )
    }
    let malformed = SensorSnapshot(
      id: "test.issue_cap",
      name: "Fixture",
      category: .diagnostics,
      summary: "Fixture",
      status: .available,
      source: "Fixture",
      capability: .publicAPI,
      channels: invalidChannels
    )

    XCTAssertEqual(
      SensorContractAudit.issues(for: [malformed]).count,
      SensorContractAudit.maximumIssueCount
    )
    XCTAssertEqual(
      SensorContractAudit.issues(providers: [], snapshots: [malformed]).count,
      SensorContractAudit.maximumIssueCount
    )
  }

  func testSnapshotGateFailsClosedWithoutEchoingMalformedProviderOutput() {
    let metadata = SensorProviderMetadata(
      id: "test.provider",
      name: "Fixture provider",
      category: .diagnostics,
      source: "Fixture source",
      capability: .publicAPI
    )
    let valid = SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "Fixture",
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: [
        SensorChannel(id: "value", label: "Value", value: 1, formattedValue: "1")
      ]
    )
    XCTAssertEqual(SensorSnapshotGate.admitted(valid, for: metadata), valid)

    let tailMarker = "SENSITIVE_PROVIDER_TAIL"
    let malformed = SensorSnapshot(
      id: String(repeating: "a", count: 10_000) + tailMarker,
      name: String(repeating: "x", count: 10_000) + tailMarker,
      category: .diagnostics,
      summary: tailMarker,
      status: .available,
      source: tailMarker,
      capability: .undocumented,
      channels: [
        SensorChannel(
          id: "value",
          label: tailMarker,
          value: .infinity,
          formattedValue: tailMarker
        )
      ],
      notes: [tailMarker]
    )
    let wrongIdentity = SensorSnapshot(
      id: "test.other",
      name: metadata.name,
      category: metadata.category,
      summary: "Fixture",
      status: .unavailable,
      source: metadata.source,
      capability: metadata.capability
    )

    for rejectedInput in [malformed, wrongIdentity] {
      let rejected = SensorSnapshotGate.admitted(rejectedInput, for: metadata)
      XCTAssertEqual(rejected.id, metadata.id)
      XCTAssertEqual(rejected.name, metadata.name)
      XCTAssertEqual(rejected.status, .error)
      XCTAssertTrue(rejected.channels.isEmpty)
      XCTAssertFalse(rejected.summary.contains(tailMarker))
      XCTAssertFalse(rejected.notes.joined().contains(tailMarker))
      XCTAssertTrue(SensorContractAudit.issues(for: [rejected]).isEmpty)
    }
  }

  func testSMCGenerationParsingUsesExactNonIdentifyingTokens() {
    XCTAssertEqual(AppleSiliconSMCGeneration.parse(cpuBrand: "Apple M1 Pro"), .m1)
    XCTAssertEqual(AppleSiliconSMCGeneration.parse(cpuBrand: "Apple M2 Max"), .m2)
    XCTAssertEqual(AppleSiliconSMCGeneration.parse(cpuBrand: "Apple M3"), .m3)
    XCTAssertEqual(AppleSiliconSMCGeneration.parse(cpuBrand: "Apple M4 Ultra"), .m4)
    XCTAssertEqual(AppleSiliconSMCGeneration.parse(cpuBrand: "Apple M5"), .m5)
    XCTAssertEqual(AppleSiliconSMCGeneration.parse(cpuBrand: "Apple M10"), .unknown)
    XCTAssertEqual(AppleSiliconSMCGeneration.parse(cpuBrand: ""), .unknown)
  }

  func testSMCGenerationCatalogsBuildPortableSnapshots() {
    let fixtures:
      [(
        generation: AppleSiliconSMCGeneration,
        cpuKey: String,
        gpuKey: String,
        auxiliaryKey: String,
        foreignCPUKey: String
      )] = [
        (.m1, "Tp09", "Tg05", "Tm02", "Tp00"),
        (.m2, "Tp1h", "Tg0f", "TaLP", "Tp00"),
        (.m3, "Tf04", "Tf14", "TaLP", "Tp00"),
        (.m4, "Te09", "Tg0G", "Tm0p", "Tp00"),
        (.m5, "Tp00", "Tg0U", "Tm0p", "Tp1h"),
      ]
    let metadata = SMCSensorProvider().metadata

    for fixture in fixtures {
      let values: [String: Double] = [
        fixture.cpuKey: 40,
        fixture.gpuKey: 45,
        fixture.auxiliaryKey: 35,
        fixture.foreignCPUKey: 99,
        "FNum": 1,
        "F0Ac": 2_000,
        "PSTR": 24,
      ]
      let snapshot = SMCSensorSnapshotBuilder(
        metadata: metadata,
        generation: fixture.generation
      ).snapshot { values[$0] }
      let channelIDs = Set(snapshot.channels.map(\.id))

      XCTAssertEqual(snapshot.status, .available, fixture.generation.rawValue)
      XCTAssertTrue(channelIDs.contains("cpu_hotspot"), fixture.generation.rawValue)
      XCTAssertTrue(channelIDs.contains("gpu_hotspot"), fixture.generation.rawValue)
      XCTAssertTrue(
        channelIDs.contains("temperature_cpu_\(fixture.cpuKey.lowercased())"),
        fixture.generation.rawValue
      )
      XCTAssertTrue(
        channelIDs.contains("temperature_gpu_\(fixture.gpuKey.lowercased())"),
        fixture.generation.rawValue
      )
      XCTAssertTrue(
        channelIDs.contains("temperature_system_\(fixture.auxiliaryKey.lowercased())"),
        fixture.generation.rawValue
      )
      XCTAssertFalse(
        channelIDs.contains("temperature_cpu_\(fixture.foreignCPUKey.lowercased())"),
        fixture.generation.rawValue
      )
      XCTAssertTrue(channelIDs.contains("fan_0"), fixture.generation.rawValue)
      XCTAssertTrue(channelIDs.contains("system_power"), fixture.generation.rawValue)
      XCTAssertTrue(SensorContractAudit.issues(for: [snapshot]).isEmpty)
    }
  }

  func testSMCCatalogKeysAreFourBytesAndUniqueWithinEachGeneration() {
    for generation in AppleSiliconSMCGeneration.allCases where generation != .unknown {
      let definitions =
        SMCSensorCatalog.cpuSensors(for: generation)
        + SMCSensorCatalog.gpuSensors(for: generation)
        + SMCSensorCatalog.auxiliarySensors(for: generation)
      let keys = definitions.map(\.key)

      XCTAssertTrue(keys.allSatisfy { $0.utf8.count == 4 }, generation.rawValue)
      XCTAssertEqual(keys.count, Set(keys).count, generation.rawValue)
    }
  }

  func testSMCUnknownGenerationUsesOnlyCommonKeysAndRejectsInvalidValues() {
    let metadata = SMCSensorProvider().metadata
    let commonValues = ["Tp00": 90.0, "TaLP": 31.0]
    let commonSnapshot = SMCSensorSnapshotBuilder(
      metadata: metadata,
      generation: .unknown
    ).snapshot { commonValues[$0] }
    let commonIDs = Set(commonSnapshot.channels.map(\.id))

    XCTAssertEqual(commonSnapshot.status, .available)
    XCTAssertTrue(commonIDs.contains("temperature_system_talp"))
    XCTAssertFalse(commonIDs.contains("temperature_cpu_tp00"))
    XCTAssertTrue(commonSnapshot.notes.joined().contains("not retained or exported"))

    let invalidValues = [
      "Tp09": Double.infinity,
      "Tg05": 111,
      "TaLP": -1,
      "FNum": 5,
      "PSTR": Double.nan,
    ]
    let invalidSnapshot = SMCSensorSnapshotBuilder(
      metadata: metadata,
      generation: .m1
    ).snapshot { invalidValues[$0] }

    XCTAssertEqual(invalidSnapshot.status, .degraded)
    XCTAssertTrue(invalidSnapshot.channels.isEmpty)
    XCTAssertTrue(SensorContractAudit.issues(for: [invalidSnapshot]).isEmpty)
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
