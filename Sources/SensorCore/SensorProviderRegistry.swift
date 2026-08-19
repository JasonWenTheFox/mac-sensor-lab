import Foundation

public enum SensorProviderRegistry {
  public static func providers() -> [any SensorProvider] {
    [
      SystemInfoProvider(),
      BatteryProvider(),
      ThermalProvider(),
      SMCSensorProvider(),
      DisplayProvider(),
      StorageProvider(),
      SPUDiscoveryProvider(),
      SPULiveProvider(),
      LidAngleProvider(),
      HardwareCapabilityProvider(),
    ]
  }

  public static func readAll() async -> [SensorSnapshot] {
    await withTaskGroup(of: SensorSnapshot.self) { group in
      for provider in providers() {
        group.addTask { await provider.read() }
      }
      var snapshots: [SensorSnapshot] = []
      for await snapshot in group {
        snapshots.append(snapshot)
      }
      return snapshots.sorted { lhs, rhs in
        let leftIndex = providers().firstIndex { $0.metadata.id == lhs.id } ?? .max
        let rightIndex = providers().firstIndex { $0.metadata.id == rhs.id } ?? .max
        return leftIndex < rightIndex
      }
    }
  }
}
