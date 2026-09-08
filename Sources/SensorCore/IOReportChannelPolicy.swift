import Foundation

/// Pure, fixture-testable policy for a possible future IOReport adapter.
///
/// This file deliberately does not declare or link the private user-space IOReport API. It only
/// accepts synthetic metadata at a narrow boundary, discards private channel names, and returns a
/// normalized experimental candidate. A shipping Provider must remain a separate decision.
enum IOReportChannelFormat: Equatable, Sendable {
  case simple
  case state
  case histogram
  case simpleArray
  case unknown(Int32)
}

struct IOReportChannelMetadata: Equatable, Sendable {
  let group: String
  let subgroup: String?
  let channel: String
  let unit: String?
  let format: IOReportChannelFormat
}

enum IOReportCandidateMetric: String, Equatable, Sendable {
  case cpuComplexResidency
  case cpuCoreResidency
  case cpuEnergy
  case gpuEnergy
  case aneEnergy
  case dramEnergy
  case pciEnergy
}

enum IOReportCandidateNormalization: Equatable, Sendable {
  /// Only same-window ratios are allowed; the private absolute residency unit is not asserted.
  case residencyRatioOnly
  /// Scale for converting a nonnegative counter delta to joules.
  case joulesPerCount(Double)
}

struct IOReportCandidate: Equatable, Sendable {
  let metric: IOReportCandidateMetric
  let normalization: IOReportCandidateNormalization
}

enum IOReportChannelPolicy {
  private static let maximumMetadataByteCount = 128
  private static let maximumUnitByteCount = 16

  /// Returns only normalized, experimental metadata. The original group, channel and topology
  /// strings must not be persisted, exported, logged, or used as stable identifiers.
  static func candidate(for metadata: IOReportChannelMetadata) -> IOReportCandidate? {
    guard isBoundedMetadata(metadata.group),
      isBoundedMetadata(metadata.channel),
      metadata.subgroup.map(isBoundedMetadata) ?? true
    else {
      return nil
    }

    if metadata.group == "CPU Stats", metadata.format == .state {
      switch metadata.subgroup {
      case "CPU Complex Performance States":
        return IOReportCandidate(
          metric: .cpuComplexResidency,
          normalization: .residencyRatioOnly
        )
      case "CPU Core Performance States":
        return IOReportCandidate(
          metric: .cpuCoreResidency,
          normalization: .residencyRatioOnly
        )
      default:
        return nil
      }
    }

    guard metadata.group == "Energy Model", metadata.subgroup == nil,
      metadata.format == .simple,
      let scale = joulesPerCount(for: metadata.unit)
    else {
      return nil
    }

    let metric: IOReportCandidateMetric
    if metadata.channel.hasSuffix("CPU Energy") {
      metric = .cpuEnergy
    } else if metadata.channel.hasSuffix("GPU Energy") {
      metric = .gpuEnergy
    } else if metadata.channel.hasPrefix("ANE") {
      metric = .aneEnergy
    } else if metadata.channel.hasPrefix("DRAM") {
      metric = .dramEnergy
    } else if metadata.channel.hasPrefix("PCI"), metadata.channel.hasSuffix("Energy") {
      metric = .pciEnergy
    } else {
      return nil
    }

    return IOReportCandidate(metric: metric, normalization: .joulesPerCount(scale))
  }

  private static func joulesPerCount(for unit: String?) -> Double? {
    guard let unit,
      isBoundedText(unit, maximumByteCount: maximumUnitByteCount)
    else {
      return nil
    }
    switch unit.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "J": return 1
    case "mJ": return 1e-3
    case "uJ", "µJ", "μJ": return 1e-6
    case "nJ": return 1e-9
    case "pJ": return 1e-12
    default: return nil
    }
  }

  private static func isBoundedMetadata(_ value: String) -> Bool {
    isBoundedText(value, maximumByteCount: maximumMetadataByteCount)
  }

  private static func isBoundedText(_ value: String, maximumByteCount: Int) -> Bool {
    guard !value.isEmpty, value.utf8.count <= maximumByteCount,
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return false
    }
    return !value.unicodeScalars.contains { scalar in
      CharacterSet.controlCharacters.contains(scalar)
    }
  }
}

enum IOReportDeltaMath {
  /// Treats negative deltas as reset/wrap/schema failure and never clamps them into plausible data.
  static func powerWatts(
    rawDelta: Int64,
    elapsedSeconds: TimeInterval,
    joulesPerCount: Double
  ) -> Double? {
    guard rawDelta >= 0, elapsedSeconds.isFinite, elapsedSeconds > 0,
      joulesPerCount.isFinite, joulesPerCount > 0
    else {
      return nil
    }
    let result = Double(rawDelta) * joulesPerCount / elapsedSeconds
    return result.isFinite && result >= 0 ? result : nil
  }

  /// Computes a dimensionless same-window share without claiming a private absolute time unit.
  static func residencyShare(active: [Int64], idle: [Int64]) -> Double? {
    guard let activeTotal = checkedTotal(active), let idleTotal = checkedTotal(idle) else {
      return nil
    }
    let total = activeTotal.addingReportingOverflow(idleTotal)
    guard !total.overflow, total.partialValue > 0 else { return nil }
    return Double(activeTotal) / Double(total.partialValue)
  }

  private static func checkedTotal(_ values: [Int64]) -> UInt64? {
    var total: UInt64 = 0
    for value in values {
      guard value >= 0 else { return nil }
      let next = total.addingReportingOverflow(UInt64(value))
      guard !next.overflow else { return nil }
      total = next.partialValue
    }
    return total
  }
}
