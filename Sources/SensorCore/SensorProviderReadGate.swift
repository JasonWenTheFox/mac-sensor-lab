import Foundation

/// Keeps one slow or stuck provider from blocking an entire read cycle.
///
/// A timed-out synchronous hardware call cannot be forcefully terminated safely. The gate instead
/// returns a bounded degraded result and refuses to start another call for that provider until the
/// original one finishes. Other providers can continue refreshing without accumulating duplicate
/// reads or blocked dashboard cycles.
public final class SensorProviderReadGate: @unchecked Sendable {
  public static let defaultTimeout: Duration = .seconds(2)

  public let metadata: SensorProviderMetadata

  private let provider: any SensorProvider
  private let stateLock = NSLock()
  private var isReadInFlight = false

  public init(provider: any SensorProvider) {
    self.provider = provider
    self.metadata = provider.metadata
  }

  public func read(timeout: Duration = defaultTimeout) async -> SensorSnapshot {
    guard !Task.isCancelled else { return slowReadSnapshot() }
    guard beginRead() else { return slowReadSnapshot() }

    let race = SensorSnapshotRace()
    let fallback = slowReadSnapshot()

    return await withTaskCancellationHandler {
      Task.detached(priority: .userInitiated) { [provider, self] in
        let snapshot = await provider.read()
        finishRead()
        race.resolve(snapshot)
      }
      let timeoutTask = Task.detached {
        do {
          try await Task.sleep(for: timeout)
        } catch {
          return
        }
        race.resolve(fallback)
      }
      let result = await race.wait()
      timeoutTask.cancel()
      return result
    } onCancel: {
      race.resolve(fallback)
    }
  }

  private func beginRead() -> Bool {
    stateLock.withLock {
      guard !isReadInFlight else { return false }
      isReadInFlight = true
      return true
    }
  }

  private func finishRead() {
    stateLock.withLock { isReadInFlight = false }
  }

  private func slowReadSnapshot() -> SensorSnapshot {
    SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "Sensor read is taking longer than expected",
      status: .degraded,
      source: metadata.source,
      capability: metadata.capability,
      notes: ["Other sensors will continue updating while this read finishes."]
    )
  }
}

private final class SensorSnapshotRace: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<SensorSnapshot, Never>?
  private var storedResult: SensorSnapshot?
  private var isResolved = false

  func wait() async -> SensorSnapshot {
    await withCheckedContinuation { continuation in
      let readyResult = lock.withLock { () -> SensorSnapshot? in
        if let storedResult {
          self.storedResult = nil
          return storedResult
        }
        self.continuation = continuation
        return nil
      }
      if let readyResult {
        continuation.resume(returning: readyResult)
      }
    }
  }

  func resolve(_ result: SensorSnapshot) {
    let waitingContinuation = lock.withLock {
      () -> CheckedContinuation<SensorSnapshot, Never>? in
      guard !isResolved else { return nil }
      isResolved = true
      guard let continuation else {
        storedResult = result
        return nil
      }
      self.continuation = nil
      return continuation
    }
    waitingContinuation?.resume(returning: result)
  }
}
