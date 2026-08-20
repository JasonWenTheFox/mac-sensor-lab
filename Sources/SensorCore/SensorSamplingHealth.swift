import Foundation

/// Bounded, value-free runtime evidence for diagnosing intermittent provider availability.
///
/// The tracker records only counters, stable provider IDs, and status categories. It never keeps
/// sensor readings, free text, wall-clock timestamps, file paths, or machine identifiers.
public struct SensorProviderSamplingHealth: Identifiable, Codable, Equatable, Sendable {
  public var id: String { providerID }

  public let providerID: String
  public let observationCount: Int
  public let statusTransitionCount: Int
  public let consecutiveIssueCount: Int
  public let lastStatus: SensorStatus
}

public struct SensorSamplingHealth: Codable, Equatable, Sendable {
  public let completedCycleCount: Int
  public let lastCycleDurationMilliseconds: UInt64?
  public let providers: [SensorProviderSamplingHealth]

  public var totalStatusTransitionCount: Int {
    providers.reduce(0) { partial, provider in
      let (sum, overflow) = partial.addingReportingOverflow(provider.statusTransitionCount)
      return overflow ? Int.max : sum
    }
  }

  public static let empty = SensorSamplingHealth(
    completedCycleCount: 0,
    lastCycleDurationMilliseconds: nil,
    providers: []
  )
}

public struct SensorSamplingHealthTracker: Sendable {
  private struct MutableProviderHealth: Sendable {
    var observationCount = 0
    var statusTransitionCount = 0
    var consecutiveIssueCount = 0
    var lastStatus: SensorStatus?
  }

  private var completedCycleCount = 0
  private var providerOrder: [String] = []
  private var providers: [String: MutableProviderHealth] = [:]

  public init() {}

  /// Records one completed dashboard cycle.
  ///
  /// Duplicate provider IDs are observed only once per cycle so malformed provider output cannot
  /// inflate the counters before the separate contract audit reports the duplicate.
  @discardableResult
  public mutating func observe(
    snapshots: [SensorSnapshot],
    cycleDuration: TimeInterval
  ) -> SensorSamplingHealth {
    completedCycleCount = saturatingIncrement(completedCycleCount)
    var seenProviderIDs: Set<String> = []

    for snapshot in snapshots where seenProviderIDs.insert(snapshot.id).inserted {
      var provider = providers[snapshot.id] ?? MutableProviderHealth()
      if providers[snapshot.id] == nil {
        providerOrder.append(snapshot.id)
      }

      provider.observationCount = saturatingIncrement(provider.observationCount)
      if let previousStatus = provider.lastStatus, previousStatus != snapshot.status {
        provider.statusTransitionCount = saturatingIncrement(provider.statusTransitionCount)
      }
      provider.consecutiveIssueCount =
        snapshot.status == .available
        ? 0 : saturatingIncrement(provider.consecutiveIssueCount)
      provider.lastStatus = snapshot.status
      providers[snapshot.id] = provider
    }

    return snapshot(cycleDuration: cycleDuration)
  }

  private func snapshot(cycleDuration: TimeInterval) -> SensorSamplingHealth {
    SensorSamplingHealth(
      completedCycleCount: completedCycleCount,
      lastCycleDurationMilliseconds: Self.milliseconds(cycleDuration),
      providers: providerOrder.compactMap { providerID in
        guard let provider = providers[providerID], let lastStatus = provider.lastStatus else {
          return nil
        }
        return SensorProviderSamplingHealth(
          providerID: providerID,
          observationCount: provider.observationCount,
          statusTransitionCount: provider.statusTransitionCount,
          consecutiveIssueCount: provider.consecutiveIssueCount,
          lastStatus: lastStatus
        )
      }
    )
  }

  private static func milliseconds(_ duration: TimeInterval) -> UInt64? {
    guard duration.isFinite, duration >= 0 else { return nil }
    let milliseconds = duration * 1_000
    guard milliseconds.isFinite, milliseconds <= Double(UInt64.max) else { return nil }
    return UInt64(milliseconds.rounded())
  }

  private func saturatingIncrement(_ value: Int) -> Int {
    value == Int.max ? value : value + 1
  }
}
