import Foundation

/// Fail-closed admission for provider output before it reaches UI, history, or recording state.
public enum SensorSnapshotGate {
  public static func admitted(
    _ snapshot: SensorSnapshot,
    for metadata: SensorProviderMetadata,
    now: Date = .now
  ) -> SensorSnapshot {
    let structuralIssues = SensorContractAudit.issues(for: [snapshot], now: now)
    guard structuralIssues.isEmpty else {
      return rejectionSnapshot(for: metadata, now: now)
    }

    guard snapshot.id == metadata.id,
      snapshot.name == metadata.name,
      snapshot.category == metadata.category,
      snapshot.source == metadata.source,
      snapshot.capability == metadata.capability
    else {
      return rejectionSnapshot(for: metadata, now: now)
    }
    return snapshot
  }

  private static func rejectionSnapshot(
    for metadata: SensorProviderMetadata,
    now: Date
  ) -> SensorSnapshot {
    let timestamp = now.timeIntervalSinceReferenceDate.isFinite ? now : .now
    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "Provider output rejected by the safety contract",
      status: .error,
      source: metadata.source,
      capability: metadata.capability,
      notes: ["Malformed provider output was discarded before display or export."],
      timestamp: timestamp
    )
  }
}
