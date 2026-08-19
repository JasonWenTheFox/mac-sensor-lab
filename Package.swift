// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MacSensorLab",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SensorCore", targets: ["SensorCore"]),
    .executable(name: "MacSensorLab", targets: ["MacSensorLab"]),
    .executable(name: "sensorlab-probe", targets: ["SensorLabProbe"]),
    .executable(name: "sensorlab-selftest", targets: ["SensorLabSelfTest"]),
  ],
  targets: [
    .target(
      name: "SensorCore",
      linkerSettings: [
        .linkedFramework("IOKit"),
        .linkedFramework("CoreGraphics"),
      ]
    ),
    .executableTarget(
      name: "MacSensorLab",
      dependencies: ["SensorCore"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("SwiftUI"),
        .linkedFramework("Charts"),
      ]
    ),
    .executableTarget(
      name: "SensorLabProbe",
      dependencies: ["SensorCore"]
    ),
    .executableTarget(
      name: "SensorLabSelfTest",
      dependencies: ["SensorCore"]
    ),
    .testTarget(
      name: "SensorCoreTests",
      dependencies: ["SensorCore"]
    ),
  ]
)
