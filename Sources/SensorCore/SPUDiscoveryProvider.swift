import Foundation
import IOKit

public struct SPUDiscoveryProvider: SensorProvider {
  public let metadata = SensorProviderMetadata(
    id: "motion.spu_discovery",
    name: "Apple SPU Sensors",
    category: .motion,
    source: "AppleSPUHIDDevice IORegistry",
    capability: .undocumented
  )

  public init() {}

  public func read() async -> SensorSnapshot {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(
      kIOMainPortDefault,
      IOServiceMatching("AppleSPUHIDDevice"),
      &iterator
    )
    guard result == kIOReturnSuccess else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "SPU enumeration failed",
        status: .error,
        source: metadata.source,
        capability: metadata.capability,
        readiness: SensorReadiness(
          hardwarePresence: .unknown,
          decoder: .notApplicable,
          readPath: .failed,
          stream: .notApplicable,
          feature: .unknown
        ),
        notes: ["IOReturn \(result)"]
      )
    }
    defer { IOObjectRelease(iterator) }

    let known: [String: (String, String)] = [
      "65280:3": ("accelerometer", "Accelerometer"),
      "65280:9": ("gyroscope", "Gyroscope"),
      "65280:4": ("ambient_light", "Ambient light"),
      "32:138": ("lid_angle", "Lid angle"),
    ]

    var found: [SensorChannel] = []
    var service = IOIteratorNext(iterator)
    while service != 0 {
      let page = IOKitHelpers.integer(service, key: "PrimaryUsagePage") ?? -1
      let usage = IOKitHelpers.integer(service, key: "PrimaryUsage") ?? -1
      if let mapped = known["\(page):\(usage)"], !found.contains(where: { $0.id == mapped.0 }) {
        found.append(
          SensorChannel(
            id: mapped.0,
            label: mapped.1,
            value: 1,
            formattedValue: "Detected",
            note: "Presence only; continuous access may require additional permission."
          ))
      }
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }

    guard !found.isEmpty else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "No known Apple SPU sensors detected",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability,
        readiness: SensorReadiness(
          hardwarePresence: .absent,
          decoder: .notApplicable,
          readPath: .ready,
          stream: .notApplicable,
          feature: .unsupported
        )
      )
    }

    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: "\(found.count) experimental sensor types detected",
      status: .degraded,
      source: metadata.source,
      capability: metadata.capability,
      readiness: SensorReadiness(
        hardwarePresence: .present,
        decoder: .notApplicable,
        readPath: .ready,
        stream: .notApplicable,
        feature: .partial
      ),
      channels: found.sorted { $0.label < $1.label },
      notes: [
        "Detection alone does not guarantee that live reports are available."
      ]
    )
  }
}
