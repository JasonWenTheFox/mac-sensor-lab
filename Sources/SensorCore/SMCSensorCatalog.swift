import Darwin
import Foundation

// Fixed generation key catalogs adapted from exelban/stats (MIT), commit
// db5fee1eae913e24a7e0c4a0395092d867cf902d.

enum AppleSiliconSMCGeneration: String, CaseIterable, Sendable {
  case m1
  case m2
  case m3
  case m4
  case m5
  case unknown

  var displayName: String {
    switch self {
    case .m1: "M1"
    case .m2: "M2"
    case .m3: "M3"
    case .m4: "M4"
    case .m5: "M5"
    case .unknown: "unknown Apple Silicon generation"
    }
  }

  static func parse(cpuBrand: String) -> Self {
    let tokens = cpuBrand.uppercased().split { !$0.isLetter && !$0.isNumber }
    for generation in [Self.m5, .m4, .m3, .m2, .m1]
    where tokens.contains(Substring(generation.rawValue.uppercased())) {
      return generation
    }
    return .unknown
  }

  static func current() -> Self {
    var byteCount = 0
    guard sysctlbyname("machdep.cpu.brand_string", nil, &byteCount, nil, 0) == 0,
      byteCount > 1, byteCount <= 128
    else { return .unknown }

    var bytes = [UInt8](repeating: 0, count: byteCount)
    let result = bytes.withUnsafeMutableBytes { buffer in
      sysctlbyname("machdep.cpu.brand_string", buffer.baseAddress, &byteCount, nil, 0)
    }
    guard result == 0 else { return .unknown }
    let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
    return parse(cpuBrand: String(decoding: bytes[..<end], as: UTF8.self))
  }
}

struct SMCTemperatureSensorDefinition: Equatable, Sendable {
  let key: String
  let label: String
}

enum SMCSensorCatalog {
  static func cpuSensors(for generation: AppleSiliconSMCGeneration)
    -> [SMCTemperatureSensorDefinition]
  {
    switch generation {
    case .m1:
      sensors([
        ("Tp09", "CPU efficiency core 1"), ("Tp0T", "CPU efficiency core 2"),
        ("Tp01", "CPU performance core 1"), ("Tp05", "CPU performance core 2"),
        ("Tp0D", "CPU performance core 3"), ("Tp0H", "CPU performance core 4"),
        ("Tp0L", "CPU performance core 5"), ("Tp0P", "CPU performance core 6"),
        ("Tp0X", "CPU performance core 7"), ("Tp0b", "CPU performance core 8"),
      ])
    case .m2:
      sensors([
        ("Tp1h", "CPU efficiency core 1"), ("Tp1t", "CPU efficiency core 2"),
        ("Tp1p", "CPU efficiency core 3"), ("Tp1l", "CPU efficiency core 4"),
        ("Tp01", "CPU performance core 1"), ("Tp05", "CPU performance core 2"),
        ("Tp09", "CPU performance core 3"), ("Tp0D", "CPU performance core 4"),
        ("Tp0X", "CPU performance core 5"), ("Tp0b", "CPU performance core 6"),
        ("Tp0f", "CPU performance core 7"), ("Tp0j", "CPU performance core 8"),
      ])
    case .m3:
      sensors([
        ("Te05", "CPU efficiency core 1"), ("Te0L", "CPU efficiency core 2"),
        ("Te0P", "CPU efficiency core 3"), ("Te0S", "CPU efficiency core 4"),
        ("Tf04", "CPU performance core 1"), ("Tf09", "CPU performance core 2"),
        ("Tf0A", "CPU performance core 3"), ("Tf0B", "CPU performance core 4"),
        ("Tf0D", "CPU performance core 5"), ("Tf0E", "CPU performance core 6"),
        ("Tf44", "CPU performance core 7"), ("Tf49", "CPU performance core 8"),
        ("Tf4A", "CPU performance core 9"), ("Tf4B", "CPU performance core 10"),
        ("Tf4D", "CPU performance core 11"), ("Tf4E", "CPU performance core 12"),
      ])
    case .m4:
      sensors([
        ("Te05", "CPU efficiency core 1"), ("Te0S", "CPU efficiency core 2"),
        ("Te09", "CPU efficiency core 3"), ("Te0H", "CPU efficiency core 4"),
        ("Tp01", "CPU performance core 1"), ("Tp05", "CPU performance core 2"),
        ("Tp09", "CPU performance core 3"), ("Tp0D", "CPU performance core 4"),
        ("Tp0V", "CPU performance core 5"), ("Tp0Y", "CPU performance core 6"),
        ("Tp0b", "CPU performance core 7"), ("Tp0e", "CPU performance core 8"),
      ])
    case .m5:
      sensors([
        ("Tp00", "CPU super core 1"), ("Tp04", "CPU super core 2"),
        ("Tp08", "CPU super core 3"), ("Tp0C", "CPU super core 4"),
        ("Tp0G", "CPU super core 5"), ("Tp0K", "CPU super core 6"),
        ("Tp0O", "CPU performance core 1"), ("Tp0R", "CPU performance core 2"),
        ("Tp0U", "CPU performance core 3"), ("Tp0X", "CPU performance core 4"),
        ("Tp0a", "CPU performance core 5"), ("Tp0d", "CPU performance core 6"),
        ("Tp0g", "CPU performance core 7"), ("Tp0j", "CPU performance core 8"),
        ("Tp0m", "CPU performance core 9"), ("Tp0p", "CPU performance core 10"),
        ("Tp0u", "CPU performance core 11"), ("Tp0y", "CPU performance core 12"),
      ])
    case .unknown:
      []
    }
  }

  static func gpuSensors(for generation: AppleSiliconSMCGeneration)
    -> [SMCTemperatureSensorDefinition]
  {
    switch generation {
    case .m1:
      sensors([
        ("Tg05", "GPU 1"), ("Tg0D", "GPU 2"), ("Tg0L", "GPU 3"),
        ("Tg0T", "GPU 4"),
      ])
    case .m2:
      sensors([("Tg0f", "GPU 1"), ("Tg0j", "GPU 2")])
    case .m3:
      sensors([
        ("Tf14", "GPU 1"), ("Tf18", "GPU 2"), ("Tf19", "GPU 3"),
        ("Tf1A", "GPU 4"), ("Tf24", "GPU 5"), ("Tf28", "GPU 6"),
        ("Tf29", "GPU 7"), ("Tf2A", "GPU 8"),
      ])
    case .m4:
      sensors([
        ("Tg0G", "GPU 1"), ("Tg0H", "GPU 2"), ("Tg1U", "GPU 1"),
        ("Tg1k", "GPU 2"), ("Tg0K", "GPU 3"), ("Tg0L", "GPU 4"),
        ("Tg0d", "GPU 5"), ("Tg0e", "GPU 6"), ("Tg0j", "GPU 7"),
        ("Tg0k", "GPU 8"),
      ])
    case .m5:
      sensors([
        ("Tg0U", "GPU 1"), ("Tg0X", "GPU 2"), ("Tg0d", "GPU 3"),
        ("Tg0g", "GPU 4"), ("Tg0j", "GPU 5"), ("Tg1Y", "GPU 6"),
        ("Tg1c", "GPU 7"), ("Tg1g", "GPU 8"),
      ])
    case .unknown:
      []
    }
  }

  static func auxiliarySensors(for generation: AppleSiliconSMCGeneration)
    -> [SMCTemperatureSensorDefinition]
  {
    var definitions = sensors([
      ("TaLP", "Airflow left"), ("TaRF", "Airflow right"),
      ("TH0x", "NAND"), ("TB1T", "Battery sensor 1"),
      ("TB2T", "Battery sensor 2"), ("TW0P", "Wi-Fi proximity"),
    ])
    switch generation {
    case .m1:
      definitions += sensors([
        ("Tm02", "Memory 1"), ("Tm06", "Memory 2"),
        ("Tm08", "Memory 3"), ("Tm09", "Memory 4"),
      ])
    case .m4, .m5:
      definitions += sensors([
        ("Tm0p", "Memory proximity 1"), ("Tm1p", "Memory proximity 2"),
        ("Tm2p", "Memory proximity 3"),
      ])
    case .m2, .m3, .unknown:
      break
    }
    return definitions
  }

  private static func sensors(_ values: [(String, String)])
    -> [SMCTemperatureSensorDefinition]
  {
    values.map { SMCTemperatureSensorDefinition(key: $0.0, label: $0.1) }
  }
}
