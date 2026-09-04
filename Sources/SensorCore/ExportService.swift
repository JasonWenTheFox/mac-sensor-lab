import Foundation

/// Versioned envelope for user-requested full snapshot exports.
///
/// v0.2 and earlier emitted an unversioned top-level array. The envelope makes later additions
/// explicit instead of asking consumers to infer a schema from whichever fields happen to exist.
public struct SensorSnapshotExport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let snapshots: [SensorSnapshot]

  public init(snapshots: [SensorSnapshot]) {
    self.schemaVersion = 1
    self.snapshots = snapshots
  }
}

public enum SensorExportService {
  public static func jsonData(_ snapshots: [SensorSnapshot], pretty: Bool = true) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting =
      pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
    return try encoder.encode(SensorSnapshotExport(snapshots: snapshots))
  }

  public static func csvData(_ snapshots: [SensorSnapshot]) -> Data {
    SensorCSVStreamEncoder.data(for: snapshots, includeHeader: true)
  }
}
