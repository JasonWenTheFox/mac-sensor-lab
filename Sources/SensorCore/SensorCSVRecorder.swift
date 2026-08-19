import Foundation

public enum SensorCSVStreamEncoder {
  public static let header =
    "provider_id,provider_name,status,source,channel_id,channel_name,raw_value,formatted_value,unit,kind,timestamp\n"

  public static func data(for snapshots: [SensorSnapshot], includeHeader: Bool) -> Data {
    var text = includeHeader ? header : ""
    let formatter = ISO8601DateFormatter()

    for snapshot in snapshots {
      let timestamp = formatter.string(from: snapshot.timestamp)
      if snapshot.channels.isEmpty {
        text += row(
          snapshot: snapshot,
          channelID: "",
          channelName: "",
          rawValue: "",
          formattedValue: "",
          unit: "",
          kind: "",
          timestamp: timestamp
        )
        continue
      }

      for channel in snapshot.channels {
        text += row(
          snapshot: snapshot,
          channelID: channel.id,
          channelName: channel.label,
          rawValue: channel.value.map { String($0) } ?? "",
          formattedValue: channel.formattedValue,
          unit: channel.unit ?? "",
          kind: channel.kind.rawValue,
          timestamp: timestamp
        )
      }
    }

    return Data(text.utf8)
  }

  public static func rowCount(for snapshots: [SensorSnapshot]) -> Int {
    snapshots.reduce(0) { total, snapshot in
      total + max(snapshot.channels.count, 1)
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
      snapshot.id,
      snapshot.name,
      snapshot.status.rawValue,
      snapshot.source,
      channelID,
      channelName,
      rawValue,
      formattedValue,
      unit,
      kind,
      timestamp,
    ].map(SensorFormatting.csvCell).joined(separator: ",") + "\n"
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
  case alreadyClosed
  case sizeLimitReached(limit: Int)

  public var errorDescription: String? {
    switch self {
    case .invalidDestination:
      "The recording destination must be a local file URL."
    case .alreadyClosed:
      "The recording has already stopped."
    case .sizeLimitReached(let limit):
      "The recording reached its \(SensorFormatting.bytes(UInt64(limit))) safety limit."
    }
  }
}

/// Append-only CSV recording with a hard byte limit and a synchronized file after every batch.
public actor SensorCSVRecorder {
  public static let defaultByteLimit = 50 * 1_024 * 1_024

  public nonisolated let destinationURL: URL
  public nonisolated let startedAt: Date

  private let byteLimit: Int
  private var handle: FileHandle?
  private var rowCount = 0
  private var byteCount: Int

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

    try headerData.write(to: destinationURL, options: .atomic)
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

    let data = SensorCSVStreamEncoder.data(for: snapshots, includeHeader: false)
    guard byteCount + data.count <= byteLimit else {
      throw SensorCSVRecorderError.sizeLimitReached(limit: byteLimit)
    }

    try handle.write(contentsOf: data)
    try handle.synchronize()
    byteCount += data.count
    rowCount += SensorCSVStreamEncoder.rowCount(for: snapshots)
    return progress()
  }

  public func finish() throws -> SensorCSVRecordingProgress {
    guard let handle else { throw SensorCSVRecorderError.alreadyClosed }
    try handle.synchronize()
    try handle.close()
    self.handle = nil
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
}
