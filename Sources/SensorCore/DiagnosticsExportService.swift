import Foundation

/// A deliberately value-free support report for issue triage.
///
/// It contains stable provider/channel identifiers and availability metadata, but never sensor
/// values, summaries, notes, source strings, machine identifiers, or user-selected file paths.
public struct SensorDiagnosticsReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let generatedAt: Date
  public let applicationVersion: String
  public let providers: [SensorProviderDiagnostic]

  public init(
    snapshots: [SensorSnapshot],
    applicationVersion: String,
    generatedAt: Date = .now
  ) {
    self.schemaVersion = 1
    self.generatedAt = generatedAt
    self.applicationVersion = applicationVersion
    self.providers = snapshots.map(SensorProviderDiagnostic.init(snapshot:))
  }
}

public struct SensorProviderDiagnostic: Codable, Equatable, Sendable {
  public let providerID: String
  public let category: SensorCategory
  public let status: SensorStatus
  public let capability: SensorCapability
  public let channels: [SensorChannelDiagnostic]

  fileprivate init(snapshot: SensorSnapshot) {
    self.providerID = snapshot.id
    self.category = snapshot.category
    self.status = snapshot.status
    self.capability = snapshot.capability
    self.channels = snapshot.channels.map(SensorChannelDiagnostic.init(channel:))
  }
}

public struct SensorChannelDiagnostic: Codable, Equatable, Sendable {
  public let channelID: String
  public let unit: String?
  public let kind: SensorValueKind

  fileprivate init(channel: SensorChannel) {
    self.channelID = channel.id
    self.unit = channel.unit
    self.kind = channel.kind
  }
}

public enum SensorDiagnosticsExportService {
  private static let blockedContractCodes: Set<SensorContractIssue.Code> = [
    .duplicateProviderIdentifier,
    .duplicateChannelIdentifier,
    .invalidStableIdentifier,
    .forbiddenIdentifier,
  ]

  public static func jsonData(
    _ snapshots: [SensorSnapshot],
    applicationVersion: String,
    generatedAt: Date = .now
  ) throws -> Data {
    if let issue = SensorContractAudit.issues(for: snapshots).first(where: {
      blockedContractCodes.contains($0.code)
    }) {
      throw SensorDiagnosticsExportError.unsafeMetadata(code: issue.code, path: issue.path)
    }
    let report = SensorDiagnosticsReport(
      snapshots: snapshots,
      applicationVersion: applicationVersion,
      generatedAt: generatedAt
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(report)
  }
}

public enum SensorDiagnosticsExportError: LocalizedError, Equatable {
  case unsafeMetadata(code: SensorContractIssue.Code, path: String)

  public var errorDescription: String? {
    switch self {
    case .unsafeMetadata(let code, let path):
      "Privacy-safe diagnostics refused unsafe metadata (\(code.rawValue) at \(path))."
    }
  }
}
