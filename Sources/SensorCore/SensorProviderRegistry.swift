import Foundation

public enum SensorProviderRegistry {
  public static func providers() -> [any SensorProvider] {
    [
      SystemInfoProvider(),
      SystemPerformanceProvider(),
      GPUPerformanceProvider(),
      NetworkThroughputProvider(),
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
    let order = Dictionary(
      uniqueKeysWithValues: providers.enumerated().map { ($0.element.metadata.id, $0.offset) })
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
}
