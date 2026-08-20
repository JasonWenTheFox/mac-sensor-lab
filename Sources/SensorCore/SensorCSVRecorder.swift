import Foundation

public enum SensorCSVStreamEncoder {
  public static let header =
    "provider_id,provider_name,status,source,channel_id,channel_name,raw_value,formatted_value,unit,kind,timestamp\n"

  public static func data(for snapshots: [SensorSnapshot], includeHeader: Bool) -> Data {
    var data = includeHeader ? Data(header.utf8) : Data()
    forEachRow(in: snapshots) { row in
      data.append(contentsOf: row.utf8)
    }
    return data
  }

  static func forEachRow(
    in snapshots: [SensorSnapshot],
    _ body: (String) throws -> Void
  ) rethrows {
    let formatter = ISO8601DateFormatter()

    for snapshot in snapshots {
      let timestamp = formatter.string(from: snapshot.timestamp)
      if snapshot.channels.isEmpty {
        try body(
          row(
            snapshot: snapshot,
            channelID: "",
            channelName: "",
            rawValue: "",
            formattedValue: "",
            unit: "",
            kind: "",
            timestamp: timestamp
          )
        )
        continue
      }

      for channel in snapshot.channels {
        try body(
          row(
            snapshot: snapshot,
            channelID: channel.id,
            channelName: channel.label,
            rawValue: channel.value.map { String($0) } ?? "",
            formattedValue: channel.formattedValue,
            unit: channel.unit ?? "",
            kind: channel.kind.rawValue,
            timestamp: timestamp
          )
        )
      }
    }
  }

  public static func rowCount(for snapshots: [SensorSnapshot]) -> Int {
    snapshots.reduce(0) { total, snapshot in
      let (sum, overflow) = total.addingReportingOverflow(max(snapshot.channels.count, 1))
      return overflow ? Int.max : sum
    }
  }

  private static func row(
    snapshot: SensorSnapshot,
    channelID: String,
    channelName: String,
    rawValue: String,
    formattedValue: String,
    unit: String,
    kind: String,
    timestamp: String
  ) -> String {
    [
      SensorFormatting.csvTextCell(snapshot.id),
      SensorFormatting.csvTextCell(snapshot.name),
      SensorFormatting.csvTextCell(snapshot.status.rawValue),
      SensorFormatting.csvTextCell(snapshot.source),
      SensorFormatting.csvTextCell(channelID),
      SensorFormatting.csvTextCell(channelName),
      SensorFormatting.csvCell(rawValue),
      SensorFormatting.csvTextCell(formattedValue),
      SensorFormatting.csvTextCell(unit),
      SensorFormatting.csvTextCell(kind),
      SensorFormatting.csvCell(timestamp),
    ].joined(separator: ",") + "\n"
  }
}

public struct SensorCSVRecordingProgress: Equatable, Sendable {
  public let destinationURL: URL
  public let startedAt: Date
  public let rowCount: Int
  public let byteCount: Int
  public let byteLimit: Int

  public var fractionUsed: Double {
    guard byteLimit > 0 else { return 1 }
    return min(Double(byteCount) / Double(byteLimit), 1)
  }
}

public enum SensorCSVRecorderError: LocalizedError, Equatable {
  case invalidDestination
  case destinationTruncated
  case alreadyClosed
  case sizeLimitReached(limit: Int)
  case unsafeSnapshot(code: SensorContractIssue.Code, path: String)
  case trackedProviderLimitReached(limit: Int)

  public var errorDescription: String? {
    switch self {
    case .invalidDestination:
      "The recording destination must be a local file URL."
    case .destinationTruncated:
      "The recording destination was truncated by another process."
    case .alreadyClosed:
      "The recording has already stopped."
    case .sizeLimitReached(let limit):
      "The recording reached its \(SensorFormatting.bytes(UInt64(limit))) safety limit."
    case .unsafeSnapshot(let code, let path):
      "Recording refused unsafe provider output (\(code.rawValue) at \(path))."
    case .trackedProviderLimitReached(let limit):
      "Recording cannot track more than \(limit) provider identities."
    }
  }
}

/// Append-only CSV recording with a hard byte limit and a synchronized file after every batch.
public actor SensorCSVRecorder {
  public static let defaultByteLimit = 50 * 1_024 * 1_024
  public static let maximumTrackedProviderCount = SensorContractAudit.maximumProviderCount

  public nonisolated let destinationURL: URL
  public nonisolated let startedAt: Date

  private let byteLimit: Int
  private var handle: FileHandle?
  private var rowCount = 0
  private var byteCount: Int
  private var lastSnapshotMarkers: [String: SnapshotMarker] = [:]

  private struct SnapshotMarker: Equatable {
    let timestamp: Date
    let status: SensorStatus
  }

  public init(
    destinationURL: URL,
    byteLimit: Int = SensorCSVRecorder.defaultByteLimit
  ) throws {
    guard destinationURL.isFileURL, byteLimit >= SensorCSVStreamEncoder.header.utf8.count else {
      throw SensorCSVRecorderError.invalidDestination
    }

    self.destinationURL = destinationURL
    self.startedAt = .now
    self.byteLimit = byteLimit
    let headerData = Data(SensorCSVStreamEncoder.header.utf8)
    self.byteCount = headerData.count

    try SensorPrivateFileWriter.write(headerData, to: destinationURL)
    let handle = try FileHandle(forWritingTo: destinationURL)
    try handle.seekToEnd()
    self.handle = handle
  }

  deinit {
    try? handle?.close()
  }

  public func append(_ snapshots: [SensorSnapshot]) throws -> SensorCSVRecordingProgress {
    guard let handle else { throw SensorCSVRecorderError.alreadyClosed }
    guard !snapshots.isEmpty else { return progress() }
    try validate(snapshots)

    let actualByteCount = try handle.seekToEnd()
    guard actualByteCount <= UInt64(Int.max) else {
      throw SensorCSVRecorderError.sizeLimitReached(limit: byteLimit)
    }
    byteCount = Int(actualByteCount)
    guard byteCount >= SensorCSVStreamEncoder.header.utf8.count else {
      throw SensorCSVRecorderError.destinationTruncated
    }
    guard byteCount <= byteLimit else {
      throw SensorCSVRecorderError.sizeLimitReached(limit: byteLimit)
    }
    let remainingByteCount = byteLimit - byteCount
    var pendingByteCount = 0
    var pendingRowCount = 0
    try SensorCSVStreamEncoder.forEachRow(in: snapshots) { row in
      let rowByteCount = row.utf8.count
      guard pendingByteCount <= remainingByteCount,
        rowByteCount <= remainingByteCount - pendingByteCount
      else {
        throw SensorCSVRecorderError.sizeLimitReached(limit: byteLimit)
      }
      pendingByteCount += rowByteCount
      pendingRowCount += 1
    }

    try SensorCSVStreamEncoder.forEachRow(in: snapshots) { row in
      try handle.write(contentsOf: Data(row.utf8))
    }
    try handle.synchronize()
    byteCount += pendingByteCount
    rowCount += pendingRowCount
    return progress()
  }

  /// Appends only provider snapshots that have a new timestamp or status.
  ///
  /// The check and write happen inside this actor, so concurrent calls from an initial flush and
  /// an automatic refresh cannot duplicate the same sample batch.
  public func appendNewSnapshots(
    _ snapshots: [SensorSnapshot]
  ) throws -> SensorCSVRecordingProgress {
    guard handle != nil else { throw SensorCSVRecorderError.alreadyClosed }
    guard !snapshots.isEmpty else { return progress() }
    try validate(snapshots)

    let newProviderCount = snapshots.lazy.filter {
      self.lastSnapshotMarkers[$0.id] == nil
    }.count
    let (trackedProviderCount, overflow) = lastSnapshotMarkers.count.addingReportingOverflow(
      newProviderCount
    )
    guard !overflow, trackedProviderCount <= Self.maximumTrackedProviderCount else {
      throw SensorCSVRecorderError.trackedProviderLimitReached(
        limit: Self.maximumTrackedProviderCount
      )
    }

    let batch = snapshots.filter { snapshot in
      lastSnapshotMarkers[snapshot.id]
        != SnapshotMarker(timestamp: snapshot.timestamp, status: snapshot.status)
    }
    guard !batch.isEmpty else { return progress() }

    let updatedProgress = try append(batch)
    for snapshot in batch {
      lastSnapshotMarkers[snapshot.id] = SnapshotMarker(
        timestamp: snapshot.timestamp,
        status: snapshot.status
      )
    }
    return updatedProgress
  }

  public func finish() throws -> SensorCSVRecordingProgress {
    guard let handle else { throw SensorCSVRecorderError.alreadyClosed }
    self.handle = nil
    var finalizationError: (any Error)?

    do {
      try handle.synchronize()
      let actualByteCount = try handle.seekToEnd()
      guard actualByteCount <= UInt64(Int.max) else {
        throw SensorCSVRecorderError.sizeLimitReached(limit: byteLimit)
      }
      byteCount = Int(actualByteCount)
    } catch {
      finalizationError = error
    }

    do {
      try handle.close()
    } catch {
      if finalizationError == nil { finalizationError = error }
    }

    if let finalizationError { throw finalizationError }
    return progress()
  }

  public func progress() -> SensorCSVRecordingProgress {
    SensorCSVRecordingProgress(
      destinationURL: destinationURL,
      startedAt: startedAt,
      rowCount: rowCount,
      byteCount: byteCount,
      byteLimit: byteLimit
    )
  }

  private func validate(_ snapshots: [SensorSnapshot]) throws {
    if let issue = SensorContractAudit.issues(for: snapshots).first {
      throw SensorCSVRecorderError.unsafeSnapshot(code: issue.code, path: issue.path)
    }
  }
}
