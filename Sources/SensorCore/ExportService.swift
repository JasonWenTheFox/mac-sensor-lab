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
    var rows = [
      "provider_id,provider_name,status,source,channel_id,channel_name,value,unit,kind,timestamp"
    ]
    let formatter = ISO8601DateFormatter()

    for snapshot in snapshots {
      if snapshot.channels.isEmpty {
        rows.append(
          [
            snapshot.id,
            snapshot.name,
            snapshot.status.rawValue,
            snapshot.source,
            "",
            "",
            "",
            "",
            "",
            formatter.string(from: snapshot.timestamp),
          ].map(SensorFormatting.csvCell).joined(separator: ","))
        continue
      }

      for channel in snapshot.channels {
        rows.append(
          [
            snapshot.id,
            snapshot.name,
            snapshot.status.rawValue,
            snapshot.source,
            channel.id,
            channel.label,
            channel.formattedValue,
            channel.unit ?? "",
            channel.kind.rawValue,
            formatter.string(from: snapshot.timestamp),
          ].map(SensorFormatting.csvCell).joined(separator: ","))
      }
    }

    return Data((rows.joined(separator: "\n") + "\n").utf8)
  }
}
