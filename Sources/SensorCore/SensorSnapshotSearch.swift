import Foundation

public enum SensorSnapshotSearch {
  public static func filter(
    _ snapshots: [SensorSnapshot],
    query: String,
    localizedDisplayText: (String) -> String = { $0 }
  ) -> [SensorSnapshot] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return snapshots }

    return snapshots.compactMap { snapshot in
      let providerFields =
        [
          snapshot.id,
          snapshot.name,
          snapshot.category.displayName,
          snapshot.status.displayName,
          snapshot.source,
          snapshot.capability.displayName,
          snapshot.domain.displayName,
          snapshot.domain.rawValue,
          snapshot.accessLevel.displayName,
          snapshot.accessLevel.rawValue,
          snapshot.compatibilityConfidence.displayName,
          snapshot.compatibilityConfidence.rawValue,
          snapshot.readiness.hardwarePresence.rawValue,
          snapshot.readiness.decoder.rawValue,
          snapshot.readiness.readPath.rawValue,
          snapshot.readiness.stream.rawValue,
          snapshot.readiness.feature.rawValue,
          snapshot.summary,
        ] + snapshot.notes
      if providerFields.contains(where: {
        matches($0, query: query)
          || matches(localizedDisplayText($0), query: query)
      }) {
        return snapshot
      }

      let channels = snapshot.channels.filter { channel in
        [
          channel.id,
          channel.label,
          channel.formattedValue,
          channel.unit,
          channel.kind.displayName,
          channel.note,
        ].compactMap { $0 }.contains(where: {
          matches($0, query: query)
            || matches(localizedDisplayText($0), query: query)
        })
      }
      guard !channels.isEmpty else { return nil }
      return SensorSnapshot(
        id: snapshot.id,
        name: snapshot.name,
        category: snapshot.category,
        summary: snapshot.summary,
        status: snapshot.status,
        source: snapshot.source,
        capability: snapshot.capability,
        domain: snapshot.domain,
        accessLevel: snapshot.accessLevel,
        compatibilityConfidence: snapshot.compatibilityConfidence,
        readiness: snapshot.readiness,
        channels: channels,
        notes: snapshot.notes,
        timestamp: snapshot.timestamp
      )
    }
  }

  private static func matches(_ candidate: String, query: String) -> Bool {
    candidate.localizedCaseInsensitiveContains(query)
  }
}
