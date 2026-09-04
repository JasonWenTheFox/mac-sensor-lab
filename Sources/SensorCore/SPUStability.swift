import Foundation
import IOKit.hid

enum SPUHIDOpenFailure {
  static func status(for results: [IOReturn]) -> SensorStatus {
    guard !results.isEmpty else { return .unavailable }
    if results.allSatisfy(isPermissionFailure) { return .permissionRequired }
    if results.contains(where: isTransientFailure) { return .degraded }
    return .error
  }

  static func summary(for results: [IOReturn]) -> String {
    switch status(for: results) {
    case .permissionRequired:
      "macOS denied access to the SPU interfaces"
    case .degraded:
      "SPU interfaces are temporarily busy"
    case .unavailable:
      "Compatible SPU interfaces were not exposed"
    default:
      "SPU interfaces were detected but could not be opened"
    }
  }

  static func note(for results: [IOReturn]) -> String? {
    guard !results.isEmpty else { return nil }
    let names = Array(Set(results.map(name))).sorted()
    return "HID open result: \(names.joined(separator: ", "))."
  }

  static func name(for result: IOReturn) -> String {
    switch result {
    case kIOReturnNotPrivileged: "not privileged"
    case kIOReturnNotPermitted: "not permitted"
    case kIOReturnExclusiveAccess: "exclusive access"
    case kIOReturnBusy: "busy"
    case kIOReturnNotOpen: "not open"
    case kIOReturnNotReady: "not ready"
    case kIOReturnTimeout: "timeout"
    default: String(format: "IOReturn 0x%08X", UInt32(bitPattern: result))
    }
  }

  private static func isPermissionFailure(_ result: IOReturn) -> Bool {
    result == kIOReturnNotPrivileged || result == kIOReturnNotPermitted
  }

  private static func isTransientFailure(_ result: IOReturn) -> Bool {
    switch result {
    case kIOReturnExclusiveAccess, kIOReturnBusy, kIOReturnNotOpen, kIOReturnNotReady,
      kIOReturnTimeout:
      true
    default:
      false
    }
  }
}

struct SPUSnapshotStabilizer {
  let graceInterval: TimeInterval
  private(set) var lastSuccessfulSnapshot: SensorSnapshot?

  init(graceInterval: TimeInterval = 12) {
    self.graceInterval = graceInterval
  }

  mutating func resolve(_ candidate: SensorSnapshot, now: Date = .now) -> SensorSnapshot {
    if candidate.status == .available, !candidate.channels.isEmpty {
      lastSuccessfulSnapshot = candidate
      return candidate
    }

    guard
      candidate.status == .degraded || candidate.status == .permissionRequired
        || candidate.status == .error,
      let recent = lastSuccessfulSnapshot
    else { return candidate }

    let age = max(0, now.timeIntervalSince(recent.timestamp))
    guard age <= graceInterval else { return candidate }

    let ageText = SensorFormatting.decimal(age, fractionDigits: 1)
    return SensorSnapshot(
      id: candidate.id,
      name: candidate.name,
      category: candidate.category,
      summary: "Recent live data • waiting for a new SPU report",
      status: .degraded,
      source: candidate.source,
      capability: candidate.capability,
      domain: candidate.domain,
      accessLevel: candidate.accessLevel,
      compatibilityConfidence: candidate.compatibilityConfidence,
      readiness: SensorReadiness(
        hardwarePresence: recent.readiness.hardwarePresence,
        decoder: recent.readiness.decoder,
        readPath: .limited,
        stream: .inactive,
        feature: .partial
      ),
      channels: recent.channels,
      notes: candidate.notes + [
        "Showing the last successful sample from \(ageText) seconds ago; its original timestamp is preserved."
      ],
      timestamp: recent.timestamp
    )
  }
}

final class SPUSnapshotCache: @unchecked Sendable {
  private let lock = NSLock()
  private var stabilizer: SPUSnapshotStabilizer

  init(graceInterval: TimeInterval = 12) {
    stabilizer = SPUSnapshotStabilizer(graceInterval: graceInterval)
  }

  func resolve(_ candidate: SensorSnapshot, now: Date = .now) -> SensorSnapshot {
    lock.withLock { stabilizer.resolve(candidate, now: now) }
  }
}
