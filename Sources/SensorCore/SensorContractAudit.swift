import Foundation

/// A machine-checkable contract that contributors can apply to provider output.
///
/// The audit intentionally examines stable identifiers and structural values only. It does not
/// inspect free-text labels, summaries, notes, or readings for privacy keywords because those
/// fields may legitimately explain the project's privacy boundary.
public enum SensorContractAudit {
  public static func issues(
    for snapshots: [SensorSnapshot],
    now: Date = .now,
    futureTolerance: TimeInterval = 5
  ) -> [SensorContractIssue] {
    var issues: [SensorContractIssue] = []
    var seenProviderIDs: Set<String> = []
    let latestAllowedTimestamp = now.addingTimeInterval(max(0, futureTolerance))

    for (snapshotIndex, snapshot) in snapshots.enumerated() {
      let providerPath = "snapshots[\(snapshotIndex)]"
      auditIdentifier(snapshot.id, at: "\(providerPath).id", into: &issues)
      if !seenProviderIDs.insert(snapshot.id).inserted {
        issues.append(
          SensorContractIssue(
            code: .duplicateProviderIdentifier,
            path: "\(providerPath).id",
            message: "Provider ID '\(snapshot.id)' appears more than once."
          ))
      }

      if !snapshot.timestamp.timeIntervalSinceReferenceDate.isFinite {
        issues.append(
          SensorContractIssue(
            code: .invalidTimestamp,
            path: "\(providerPath).timestamp",
            message: "Snapshot timestamp is not finite."
          ))
      } else if snapshot.timestamp > latestAllowedTimestamp {
        issues.append(
          SensorContractIssue(
            code: .futureTimestamp,
            path: "\(providerPath).timestamp",
            message: "Snapshot timestamp exceeds the allowed future tolerance."
          ))
      }

      var seenChannelIDs: Set<String> = []
      for (channelIndex, channel) in snapshot.channels.enumerated() {
        let channelPath = "\(providerPath).channels[\(channelIndex)]"
        auditIdentifier(channel.id, at: "\(channelPath).id", into: &issues)
        if !seenChannelIDs.insert(channel.id).inserted {
          issues.append(
            SensorContractIssue(
              code: .duplicateChannelIdentifier,
              path: "\(channelPath).id",
              message: "Channel ID '\(channel.id)' is duplicated within provider '\(snapshot.id)'."
            ))
        }
        if let value = channel.value, !value.isFinite {
          issues.append(
            SensorContractIssue(
              code: .nonFiniteValue,
              path: "\(channelPath).value",
              message: "Channel numeric value must be finite."
            ))
        }
        if channel.formattedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          issues.append(
            SensorContractIssue(
              code: .emptyFormattedValue,
              path: "\(channelPath).formattedValue",
              message: "Channel formatted value must not be blank."
            ))
        }
        if let unit = channel.unit,
          unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          issues.append(
            SensorContractIssue(
              code: .emptyUnit,
              path: "\(channelPath).unit",
              message: "A present channel unit must not be blank."
            ))
        }
      }
    }

    return issues
  }

  public static func issues(
    providers: [any SensorProvider],
    snapshots: [SensorSnapshot],
    now: Date = .now,
    futureTolerance: TimeInterval = 5
  ) -> [SensorContractIssue] {
    var issues: [SensorContractIssue] = []
    var metadataByID: [String: SensorProviderMetadata] = [:]

    for (providerIndex, provider) in providers.enumerated() {
      let metadata = provider.metadata
      let path = "providers[\(providerIndex)].metadata.id"
      auditIdentifier(metadata.id, at: path, into: &issues)
      if metadataByID[metadata.id] != nil {
        issues.append(
          SensorContractIssue(
            code: .duplicateProviderIdentifier,
            path: path,
            message: "Provider ID '\(metadata.id)' is registered more than once."
          ))
      } else {
        metadataByID[metadata.id] = metadata
      }
    }

    issues += self.issues(
      for: snapshots,
      now: now,
      futureTolerance: futureTolerance
    )

    let expectedIDs = Set(metadataByID.keys)
    let actualIDs = Set(snapshots.map(\.id))
    for id in expectedIDs.subtracting(actualIDs).sorted() {
      issues.append(
        SensorContractIssue(
          code: .missingProviderSnapshot,
          path: "providers.\(id)",
          message: "Registered provider did not return a snapshot."
        ))
    }
    for id in actualIDs.subtracting(expectedIDs).sorted() {
      issues.append(
        SensorContractIssue(
          code: .unexpectedProviderIdentifier,
          path: "snapshots.\(id)",
          message: "Snapshot does not match a registered provider ID."
        ))
    }

    for (snapshotIndex, snapshot) in snapshots.enumerated() {
      guard let metadata = metadataByID[snapshot.id] else { continue }
      let path = "snapshots[\(snapshotIndex)]"
      if snapshot.name != metadata.name {
        issues.append(metadataMismatch(at: "\(path).name", field: "name"))
      }
      if snapshot.category != metadata.category {
        issues.append(metadataMismatch(at: "\(path).category", field: "category"))
      }
      if snapshot.source != metadata.source {
        issues.append(metadataMismatch(at: "\(path).source", field: "source"))
      }
      if snapshot.capability != metadata.capability {
        issues.append(metadataMismatch(at: "\(path).capability", field: "capability"))
      }
    }

    return issues
  }

  private static let forbiddenIdentifierFragments = [
    "serial", "uuid", "udid", "username", "hostname", "ssid", "bssid", "mac_address",
  ]

  private static func auditIdentifier(
    _ identifier: String,
    at path: String,
    into issues: inout [SensorContractIssue]
  ) {
    if !isStableIdentifier(identifier) {
      issues.append(
        SensorContractIssue(
          code: .invalidStableIdentifier,
          path: path,
          message:
            "Stable IDs must use lowercase ASCII letters, digits, dots, or underscores and begin and end with a letter or digit."
        ))
    }
    let lowercaseIdentifier = identifier.lowercased()
    if forbiddenIdentifierFragments.contains(where: lowercaseIdentifier.contains) {
      issues.append(
        SensorContractIssue(
          code: .forbiddenIdentifier,
          path: path,
          message: "Stable ID names an identifying field that this project does not collect."
        ))
    }
  }

  private static func isStableIdentifier(_ identifier: String) -> Bool {
    guard let first = identifier.unicodeScalars.first,
      let last = identifier.unicodeScalars.last,
      isASCIIAlphanumeric(first),
      isASCIIAlphanumeric(last)
    else { return false }

    return identifier.unicodeScalars.allSatisfy { scalar in
      isASCIIAlphanumeric(scalar) || scalar == "." || scalar == "_"
    }
  }

  private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
    let value = scalar.value
    return (97...122).contains(value) || (48...57).contains(value)
  }

  private static func metadataMismatch(at path: String, field: String) -> SensorContractIssue {
    SensorContractIssue(
      code: .providerMetadataMismatch,
      path: path,
      message: "Snapshot \(field) does not match its registered provider metadata."
    )
  }
}

public struct SensorContractIssue: Equatable, Sendable, CustomStringConvertible {
  public enum Code: String, Equatable, Sendable {
    case duplicateProviderIdentifier
    case duplicateChannelIdentifier
    case invalidStableIdentifier
    case forbiddenIdentifier
    case unexpectedProviderIdentifier
    case missingProviderSnapshot
    case providerMetadataMismatch
    case nonFiniteValue
    case emptyFormattedValue
    case emptyUnit
    case invalidTimestamp
    case futureTimestamp
  }

  public let code: Code
  public let path: String
  public let message: String

  public init(code: Code, path: String, message: String) {
    self.code = code
    self.path = path
    self.message = message
  }

  public var description: String {
    "contract \(code.rawValue) at \(path): \(message)"
  }
}
