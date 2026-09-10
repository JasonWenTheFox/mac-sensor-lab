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
      name: "CNVMeSMART",
      linkerSettings: [
        .linkedFramework("DiskArbitration"),
        .linkedFramework("IOKit"),
      ]
    ),
    .target(
      name: "SensorCore",
      dependencies: ["CNVMeSMART"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("IOKit"),
        .linkedFramework("IOUSBHost"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("CoreWLAN"),
        .linkedFramework("DiskArbitration"),
        .linkedFramework("LocalAuthentication"),
        .linkedFramework("Metal"),
      ]
    ),
    .executableTarget(
      name: "MacSensorLab",
      dependencies: ["SensorCore"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("AVFAudio"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("Accelerate"),
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
    .testTarget(
      name: "MacSensorLabTests",
      dependencies: ["MacSensorLab", "SensorCore"]
    ),
  ]
)
