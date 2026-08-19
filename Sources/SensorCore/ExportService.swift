import Foundation

public enum SensorExportService {
  public static func jsonData(_ snapshots: [SensorSnapshot], pretty: Bool = true) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting =
      pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
    return try encoder.encode(snapshots)
  }

  public static func csvData(_ snapshots: [SensorSnapshot]) -> Data {
    SensorCSVStreamEncoder.data(for: snapshots, includeHeader: true)
  }
}
