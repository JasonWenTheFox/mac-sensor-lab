import Foundation

public struct SensorHistoryPoint: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let timestamp: Date
  public let value: Double

  public init(timestamp: Date, value: Double) {
    self.id = UUID()
    self.timestamp = timestamp
    self.value = value
  }
}

/// A bounded, memory-only chart history policy.
///
/// Only channels used by current charts or history-derived experiments are retained. Provider and
/// channel IDs are bounded before constructing dictionary keys, and malformed or stale samples are
/// discarded rather than allowing unbounded series growth.
public enum SensorHistoryRetention {
  public static let maximumSeriesCount = 256
  public static let maximumPointsPerSeries = 600

  public static let overviewChannelPriority = [
    "cpu_utilization",
    "gpu_device_utilization",
    "network_receive_rate",
    "disk_read_rate",
    "cpu_hotspot",
    "system_power",
    "charge",
    "angle",
    "ambient_intensity",
  ]

  public static let retainedChannelIDs = Set(
    overviewChannelPriority
      + [
        "acceleration_magnitude",
        "battery_charge",
        "thermal_pressure_level",
        "network_send_rate",
        "disk_write_rate",
      ]
  )

  public static func append(
    _ snapshot: SensorSnapshot,
    to history: inout [String: [SensorHistoryPoint]]
  ) {
    append(
      snapshot,
      to: &history,
      maximumSeriesCount: maximumSeriesCount,
      maximumPointsPerSeries: maximumPointsPerSeries
    )
  }

  static func append(
    _ snapshot: SensorSnapshot,
    to history: inout [String: [SensorHistoryPoint]],
    maximumSeriesCount requestedSeriesCount: Int,
    maximumPointsPerSeries requestedPointCount: Int
  ) {
    let seriesLimit = min(max(0, requestedSeriesCount), maximumSeriesCount)
    let pointLimit = min(max(0, requestedPointCount), maximumPointsPerSeries)
    guard seriesLimit > 0, pointLimit > 0 else { return }
    guard snapshot.timestamp.timeIntervalSinceReferenceDate.isFinite else { return }
    guard hasBoundedIdentifier(snapshot.id) else { return }

    for channel in snapshot.channels.prefix(SensorContractAudit.maximumChannelsPerProvider) {
      guard hasBoundedIdentifier(channel.id), retainedChannelIDs.contains(channel.id) else {
        continue
      }
      guard let value = channel.value, value.isFinite else { continue }

      let key = "\(snapshot.id)/\(channel.id)"
      guard history[key] != nil || history.count < seriesLimit else { continue }
      var points = history[key, default: []]
      guard points.last.map({ snapshot.timestamp > $0.timestamp }) ?? true else { continue }

      points.append(SensorHistoryPoint(timestamp: snapshot.timestamp, value: value))
      if points.count > pointLimit {
        points.removeFirst(points.count - pointLimit)
      }
      history[key] = points
    }
  }

  private static func hasBoundedIdentifier(_ identifier: String) -> Bool {
    !identifier.isEmpty
      && identifier.utf8.prefix(SensorContractAudit.maximumIdentifierByteCount + 1).count
        <= SensorContractAudit.maximumIdentifierByteCount
  }
}
