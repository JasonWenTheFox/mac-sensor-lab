import Foundation

public enum SensorProviderRegistry {
  public static func providers() -> [any SensorProvider] {
    [
      SystemInfoProvider(),
      SystemPerformanceProvider(),
      GPUPerformanceProvider(),
      NetworkThroughputProvider(),
      PublicPowerSourceProvider(),
      BatteryProvider(),
      ThermalProvider(),
      SMCSensorProvider(),
      DisplayProvider(),
      StorageProvider(),
      DiskIOProvider(),
      SPUDiscoveryProvider(),
      SPULiveProvider(),
      LidAngleProvider(),
      HardwareCapabilityProvider(),
    ]
  }

  public static func readAll() async -> [SensorSnapshot] {
    await readAll(providers())
  }

  public static func readAll(_ providers: [any SensorProvider]) async -> [SensorSnapshot] {
    let order = registrationOrder(for: providers)
    return await withTaskGroup(of: SensorSnapshot.self) { group in
      for provider in providers {
        group.addTask { await provider.read() }
      }
      var snapshots: [SensorSnapshot] = []
      for await snapshot in group {
        snapshots.append(snapshot)
      }
      return snapshots.sorted { lhs, rhs in
        (order[lhs.id] ?? .max) < (order[rhs.id] ?? .max)
      }
    }
  }

  /// Returns the first registered position for each provider ID without trapping on duplicates.
  ///
  /// Duplicate IDs remain visible in provider output so `SensorContractAudit` can report them.
  /// This helper only makes ordering defensive; it does not treat duplicates as valid.
  public static func registrationOrder(
    for providers: [any SensorProvider]
  ) -> [String: Int] {
    var order: [String: Int] = [:]
    for (index, provider) in providers.enumerated() where order[provider.metadata.id] == nil {
      order[provider.metadata.id] = index
    }
    return order
  }
}
