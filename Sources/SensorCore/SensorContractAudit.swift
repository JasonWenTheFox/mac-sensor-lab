import Foundation

/// A machine-checkable contract that contributors can apply to provider output.
///
/// The audit never scans free text or readings for privacy keywords because those fields may
/// legitimately explain the project's privacy boundary. It does enforce blank/size/cardinality
/// limits so malformed provider output cannot create misleading or unbounded UI/export payloads.
public enum SensorContractAudit {
  public static let maximumProviderCount = 256
  public static let maximumChannelsPerProvider = 1_024
  public static let maximumNotesPerProvider = 64
  public static let maximumIdentifierByteCount = 128
  public static let maximumDisplayTextByteCount = 4_096
  public static let maximumUnitByteCount = 64
  public static let maximumIssueCount = 4_096

  public static func issues(
    for snapshots: [SensorSnapshot],
    now: Date = .now,
    futureTolerance: TimeInterval = 5
  ) -> [SensorContractIssue] {
    var issues: [SensorContractIssue] = []
    var seenProviderIDs: Set<String> = []
    let latestAllowedTimestamp = latestAllowedTimestamp(
      now: now,
      futureTolerance: futureTolerance
    )

    if snapshots.count > maximumProviderCount {
      issues.append(
        SensorContractIssue(
          code: .tooManyProviders,
          path: "snapshots",
          message: "Snapshot count exceeds the \(maximumProviderCount)-provider safety limit."
        ))
    }

    snapshotLoop: for (snapshotIndex, snapshot) in snapshots.prefix(maximumProviderCount)
      .enumerated()
    {
      guard issues.count < maximumIssueCount else { break }
      let providerPath = "snapshots[\(snapshotIndex)]"
      auditIdentifier(snapshot.id, at: "\(providerPath).id", into: &issues)
      auditRequiredText(snapshot.name, at: "\(providerPath).name", into: &issues)
      auditRequiredText(snapshot.summary, at: "\(providerPath).summary", into: &issues)
      auditRequiredText(snapshot.source, at: "\(providerPath).source", into: &issues)
      if let providerID = boundedIdentifier(snapshot.id),
        !seenProviderIDs.insert(providerID).inserted
      {
        issues.append(
          SensorContractIssue(
            code: .duplicateProviderIdentifier,
            path: "\(providerPath).id",
            message: "Provider ID '\(providerID)' appears more than once."
          ))
      }

      if snapshot.status == .loading {
        issues.append(
          SensorContractIssue(
            code: .unexpectedLoadingStatus,
            path: "\(providerPath).status",
            message: "A completed provider read must not return the loading placeholder status."
          ))
      }
      if snapshot.status == .available, snapshot.channels.isEmpty {
        issues.append(
          SensorContractIssue(
            code: .availableWithoutChannels,
            path: "\(providerPath).channels",
            message: "An available provider must expose at least one channel."
          ))
      }
      if snapshot.channels.count > maximumChannelsPerProvider {
        issues.append(
          SensorContractIssue(
            code: .tooManyChannels,
            path: "\(providerPath).channels",
            message:
              "Channel count exceeds the \(maximumChannelsPerProvider)-channel safety limit."
          ))
      }
      if snapshot.notes.count > maximumNotesPerProvider {
        issues.append(
          SensorContractIssue(
            code: .tooManyNotes,
            path: "\(providerPath).notes",
            message: "Note count exceeds the \(maximumNotesPerProvider)-note safety limit."
          ))
      }
      guard issues.count < maximumIssueCount else { break }

      var seenNotes: Set<String> = []
      for (noteIndex, note) in snapshot.notes.prefix(maximumNotesPerProvider).enumerated() {
        guard issues.count < maximumIssueCount else { break snapshotLoop }
        let notePath = "\(providerPath).notes[\(noteIndex)]"
        let isBounded = auditRequiredText(note, at: notePath, into: &issues)
        if isBounded, !seenNotes.insert(note).inserted {
          issues.append(
            SensorContractIssue(
              code: .duplicateNote,
              path: notePath,
              message: "Provider notes must be unique for stable SwiftUI identity."
            ))
        }
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
      guard issues.count < maximumIssueCount else { break }

      var seenChannelIDs: Set<String> = []
      for (channelIndex, channel) in snapshot.channels.prefix(maximumChannelsPerProvider)
        .enumerated()
      {
        guard issues.count < maximumIssueCount else { break snapshotLoop }
        let channelPath = "\(providerPath).channels[\(channelIndex)]"
        auditIdentifier(channel.id, at: "\(channelPath).id", into: &issues)
        auditRequiredText(channel.label, at: "\(channelPath).label", into: &issues)
        if let note = channel.note {
          auditRequiredText(note, at: "\(channelPath).note", into: &issues)
        }
        if let channelID = boundedIdentifier(channel.id),
          !seenChannelIDs.insert(channelID).inserted
        {
          issues.append(
            SensorContractIssue(
              code: .duplicateChannelIdentifier,
              path: "\(channelPath).id",
              message: "Channel ID '\(channelID)' is duplicated within a provider."
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
        if exceedsUTF8ByteLimit(
          channel.formattedValue,
          limit: maximumDisplayTextByteCount
        ) {
          issues.append(
            SensorContractIssue(
              code: .oversizedText,
              path: "\(channelPath).formattedValue",
              message:
                "Formatted values must not exceed \(maximumDisplayTextByteCount) UTF-8 bytes."
            ))
        } else if channel.formattedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          issues.append(
            SensorContractIssue(
              code: .emptyFormattedValue,
              path: "\(channelPath).formattedValue",
              message: "Channel formatted value must not be blank."
            ))
        }
        if let unit = channel.unit {
          if exceedsUTF8ByteLimit(unit, limit: maximumUnitByteCount) {
            issues.append(
              SensorContractIssue(
                code: .oversizedText,
                path: "\(channelPath).unit",
                message: "Units must not exceed \(maximumUnitByteCount) UTF-8 bytes."
              ))
          } else if unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
              SensorContractIssue(
                code: .emptyUnit,
                path: "\(channelPath).unit",
                message: "A present channel unit must not be blank."
              ))
          }
        }
      }
    }

    return Array(issues.prefix(maximumIssueCount))
  }

  public static func issues(
    providers: [any SensorProvider],
    snapshots: [SensorSnapshot],
    now: Date = .now,
    futureTolerance: TimeInterval = 5
  ) -> [SensorContractIssue] {
    var issues: [SensorContractIssue] = []
    var metadataByID: [String: SensorProviderMetadata] = [:]

    if providers.count > maximumProviderCount {
      issues.append(
        SensorContractIssue(
          code: .tooManyProviders,
          path: "providers",
          message: "Provider count exceeds the \(maximumProviderCount)-provider safety limit."
        ))
    }

    for (providerIndex, provider) in providers.prefix(maximumProviderCount).enumerated() {
      let metadata = provider.metadata
      let path = "providers[\(providerIndex)].metadata.id"
      auditIdentifier(metadata.id, at: path, into: &issues)
      auditRequiredText(
        metadata.name,
        at: "providers[\(providerIndex)].metadata.name",
        into: &issues
      )
      auditRequiredText(
        metadata.source,
        at: "providers[\(providerIndex)].metadata.source",
        into: &issues
      )
      guard let metadataID = boundedIdentifier(metadata.id) else { continue }
      if metadataByID[metadataID] != nil {
        issues.append(
          SensorContractIssue(
            code: .duplicateProviderIdentifier,
            path: path,
            message: "Provider ID '\(metadataID)' is registered more than once."
          ))
      } else {
        metadataByID[metadataID] = metadata
      }
    }

    let snapshotIssues = self.issues(
      for: snapshots,
      now: now,
      futureTolerance: futureTolerance
    )
    issues.append(
      contentsOf: snapshotIssues.prefix(max(0, maximumIssueCount - issues.count))
    )
    guard issues.count < maximumIssueCount else { return issues }

    let expectedIDs = Set(metadataByID.keys)
    let actualIDs = Set(
      snapshots.prefix(maximumProviderCount).compactMap { boundedIdentifier($0.id) }
    )
    for id in expectedIDs.subtracting(actualIDs).sorted() {
      guard issues.count < maximumIssueCount else { break }
      issues.append(
        SensorContractIssue(
          code: .missingProviderSnapshot,
          path: "providers.\(id)",
          message: "Registered provider did not return a snapshot."
        ))
    }
    for id in actualIDs.subtracting(expectedIDs).sorted() {
      guard issues.count < maximumIssueCount else { break }
      issues.append(
        SensorContractIssue(
          code: .unexpectedProviderIdentifier,
          path: "snapshots.\(id)",
          message: "Snapshot does not match a registered provider ID."
        ))
    }

    for (snapshotIndex, snapshot) in snapshots.prefix(maximumProviderCount).enumerated() {
      guard issues.count < maximumIssueCount else { break }
      guard let snapshotID = boundedIdentifier(snapshot.id),
        let metadata = metadataByID[snapshotID]
      else { continue }
      let path = "snapshots[\(snapshotIndex)]"
      if isBoundedDisplayText(snapshot.name), isBoundedDisplayText(metadata.name),
        snapshot.name != metadata.name
      {
        issues.append(metadataMismatch(at: "\(path).name", field: "name"))
      }
      if snapshot.category != metadata.category {
        issues.append(metadataMismatch(at: "\(path).category", field: "category"))
      }
      if isBoundedDisplayText(snapshot.source), isBoundedDisplayText(metadata.source),
        snapshot.source != metadata.source
      {
        issues.append(metadataMismatch(at: "\(path).source", field: "source"))
      }
      if snapshot.capability != metadata.capability {
        issues.append(metadataMismatch(at: "\(path).capability", field: "capability"))
      }
      if snapshot.domain != metadata.domain {
        issues.append(metadataMismatch(at: "\(path).domain", field: "domain"))
      }
      if snapshot.accessLevel != metadata.accessLevel {
        issues.append(metadataMismatch(at: "\(path).accessLevel", field: "accessLevel"))
      }
      if snapshot.compatibilityConfidence != metadata.compatibilityConfidence {
        issues.append(
          metadataMismatch(
            at: "\(path).compatibilityConfidence",
            field: "compatibilityConfidence"
          ))
      }
    }

    return Array(issues.prefix(maximumIssueCount))
  }

  private static let forbiddenIdentifierFragments = [
    "serial", "uuid", "udid", "username", "hostname", "ssid", "bssid", "mac_address",
    "device_id", "machine_id", "hardware_id",
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
            "Stable IDs must be 1...\(maximumIdentifierByteCount) bytes, use lowercase ASCII letters, digits, dots, or underscores, and begin and end with a letter or digit."
        ))
    }
    guard boundedIdentifier(identifier) != nil else { return }
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
    guard !identifier.isEmpty, boundedIdentifier(identifier) != nil else {
      return false
    }
    guard let first = identifier.unicodeScalars.first,
      let last = identifier.unicodeScalars.last,
      isASCIIAlphanumeric(first),
      isASCIIAlphanumeric(last)
    else { return false }

    return identifier.unicodeScalars.allSatisfy { scalar in
      isASCIIAlphanumeric(scalar) || scalar == "." || scalar == "_"
    }
  }

  @discardableResult
  private static func auditRequiredText(
    _ value: String,
    at path: String,
    into issues: inout [SensorContractIssue]
  ) -> Bool {
    if !isBoundedDisplayText(value) {
      issues.append(
        SensorContractIssue(
          code: .oversizedText,
          path: path,
          message: "Display text must not exceed \(maximumDisplayTextByteCount) UTF-8 bytes."
        ))
      return false
    }
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(
        SensorContractIssue(
          code: .emptyText,
          path: path,
          message: "Required display text must not be blank."
        ))
    }
    return true
  }

  private static func boundedIdentifier(_ identifier: String) -> String? {
    exceedsUTF8ByteLimit(identifier, limit: maximumIdentifierByteCount) ? nil : identifier
  }

  private static func isBoundedDisplayText(_ value: String) -> Bool {
    !exceedsUTF8ByteLimit(value, limit: maximumDisplayTextByteCount)
  }

  private static func exceedsUTF8ByteLimit(_ value: String, limit: Int) -> Bool {
    value.utf8.prefix(limit + 1).count > limit
  }

  private static func latestAllowedTimestamp(
    now: Date,
    futureTolerance: TimeInterval
  ) -> Date {
    let referenceNow = now.timeIntervalSinceReferenceDate.isFinite ? now : .now
    let tolerance = futureTolerance.isFinite ? max(0, futureTolerance) : 0
    let latestReferenceTime = referenceNow.timeIntervalSinceReferenceDate + tolerance
    guard latestReferenceTime.isFinite else { return referenceNow }
    return Date(timeIntervalSinceReferenceDate: latestReferenceTime)
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
  public enum Code: String, Hashable, Sendable {
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
    case tooManyProviders
    case tooManyChannels
    case tooManyNotes
    case emptyText
    case oversizedText
    case duplicateNote
    case availableWithoutChannels
    case unexpectedLoadingStatus
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
