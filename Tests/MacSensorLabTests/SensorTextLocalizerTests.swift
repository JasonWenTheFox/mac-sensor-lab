import Foundation
import SensorCore
import XCTest

@testable import MacSensorLab

final class SensorTextLocalizerTests: XCTestCase {
  private let translations = [
    "%@ %@": "%@ %@",
    "%@ available": "可用空间 %@",
    "%@ • %@": "%@ • %@",
    "%@ • %@ memory": "%@ • %@ 内存",
    "%@ • %lld active": "%@ • %lld 台活动显示器",
    "%lld active displays": "%lld 台活动显示器",
    "%lld experimental sensor types detected": "检测到 %lld 类实验性传感器",
    "%lld of %lld capabilities detected": "已检测到 %lld/%lld 项能力",
    "%lld read-only channels": "%lld 个只读通道",
    ", ": "、",
    "AC power": "交流电源",
    "Acceleration": "加速度",
    "Battery": "电池",
    "CPU %@": "CPU %@",
    "CPU hotspot %@ °C": "CPU 热点 %@ °C",
    "Collecting activity baseline • %lld block devices": "正在建立活动基线 • %lld 个块设备",
    "Collecting CPU baseline • load %@": "正在建立 CPU 基线 • 负载 %@",
    "Collecting network baseline • %lld active interfaces": "正在建立网络基线 • %lld 个活动接口",
    "Fan %lld": "风扇 %lld",
    "GPU %@": "GPU %@",
    "HID open result: %@.": "HID 打开结果：%@。",
    "Live %@ data": "实时%@数据",
    "Load average (%lld min)": "平均负载（%lld 分钟）",
    "M4": "M4",
    "Nominal": "正常",
    "Only a fixed %@ and generation-neutral allowlist of temperature, fan and power keys was read.":
      "仅读取固定的 %@ 与代际中立温度、风扇和功率键白名单。",
    "Raw read-only SMC key %@; model-specific meaning.": "原始只读 SMC 键 %@；含义因机型而异。",
    "Read %@ • Write %@": "读取 %@ • 写入 %@",
    "SMC opened, but the %@ key allowlist returned no readings": "SMC 已打开，但 %@ 键白名单没有返回读数",
    "Showing the last successful sample from %@ seconds ago; its original timestamp is preserved.":
      "显示 %@ 秒前最后一次成功采样；保留其原始时间戳。",
    "Spectral channel %lld": "光谱通道 %lld",
    "Thermal pressure %@": "热压力%@",
    "ambient light": "环境光",
    "accelerometer": "加速度计",
    "gyroscope": "陀螺仪",
  ]

  private var localizer: SensorTextLocalizer {
    SensorTextLocalizer(
      localize: { self.translations[$0] ?? $0 },
      locale: Locale(identifier: "zh-Hans")
    )
  }

  func testLocalizesDynamicChannelLabelsAndValues() {
    XCTAssertEqual(localizer.localized("Load average (15 min)"), "平均负载（15 分钟）")
    XCTAssertEqual(localizer.localized("Fan 2"), "风扇 2")
    XCTAssertEqual(localizer.localized("Spectral channel 4"), "光谱通道 4")
    XCTAssertEqual(localizer.localized("Acceleration X"), "加速度 X")
    XCTAssertEqual(localizer.localized("Battery"), "电池")
  }

  func testLocalizesBoundedDynamicSummaries() {
    XCTAssertEqual(
      localizer.localized("Apple Silicon • 32 GB memory"),
      "Apple Silicon • 32 GB 内存"
    )
    XCTAssertEqual(
      localizer.localized("3024 × 1964 px • 1 active"),
      "3024 × 1964 px • 1 台活动显示器"
    )
    XCTAssertEqual(localizer.localized("2 active displays"), "2 台活动显示器")
    XCTAssertEqual(localizer.localized("CPU 38%"), "CPU 38%")
    XCTAssertEqual(localizer.localized("GPU 27%"), "GPU 27%")
    XCTAssertEqual(localizer.localized("Thermal pressure nominal"), "热压力正常")
    XCTAssertEqual(
      localizer.localized("Collecting network baseline • 3 active interfaces"),
      "正在建立网络基线 • 3 个活动接口"
    )
    XCTAssertEqual(
      localizer.localized("Collecting activity baseline • 2 block devices"),
      "正在建立活动基线 • 2 个块设备"
    )
    XCTAssertEqual(
      localizer.localized("Collecting CPU baseline • load 1.42"),
      "正在建立 CPU 基线 • 负载 1.42"
    )
    XCTAssertEqual(localizer.localized("Read 18 MB/s • Write 4 MB/s"), "读取 18 MB/s • 写入 4 MB/s")
    XCTAssertEqual(localizer.localized("78% • Battery"), "78% • 电池")
    XCTAssertEqual(localizer.localized("3 of 4 capabilities detected"), "已检测到 3/4 项能力")
    XCTAssertEqual(localizer.localized("3 experimental sensor types detected"), "检测到 3 类实验性传感器")
    XCTAssertEqual(localizer.localized("7 read-only channels"), "7 个只读通道")
    XCTAssertEqual(localizer.localized("CPU hotspot 54.2 °C"), "CPU 热点 54.2 °C")
    XCTAssertEqual(
      localizer.localized("Live accelerometer, gyroscope, ambient light data"),
      "实时加速度计、陀螺仪、环境光数据"
    )
    XCTAssertEqual(localizer.localized("438 GB available"), "可用空间 438 GB")
  }

  func testLocalizesBoundedDynamicNotesWithoutTouchingUnknownText() {
    XCTAssertEqual(
      localizer.localized(
        "Showing the last successful sample from 3.5 seconds ago; its original timestamp is preserved."
      ),
      "显示 3.5 秒前最后一次成功采样；保留其原始时间戳。"
    )
    XCTAssertEqual(
      localizer.localized("Raw read-only SMC key Tp01; model-specific meaning."),
      "原始只读 SMC 键 Tp01；含义因机型而异。"
    )
    XCTAssertEqual(
      localizer.localized(
        "Only a fixed M4 and generation-neutral allowlist of temperature, fan and power keys was read."
      ),
      "仅读取固定的 M4 与代际中立温度、风扇和功率键白名单。"
    )
    XCTAssertEqual(
      localizer.localized("HID open result: busy, timeout."), "HID 打开结果：busy, timeout。")
    XCTAssertEqual(
      localizer.localized("Driver text outside the allowlist"), "Driver text outside the allowlist")
  }

  func testLocalizedDynamicTextCanBeSearchedWithoutMutatingSnapshot() {
    let snapshot = SensorSnapshot(
      id: "thermal.smc",
      name: "SMC Sensors",
      category: .thermal,
      summary: "CPU hotspot 54.2 °C",
      status: .available,
      source: "Fixture",
      capability: .undocumented,
      channels: [
        SensorChannel(id: "fan_0", label: "Fan 1", value: 1_800, formattedValue: "1800")
      ]
    )

    let result = SensorSnapshotSearch.filter(
      [snapshot],
      query: "风扇",
      localizedDisplayText: localizer.localized
    )

    XCTAssertEqual(result.first?.channels.map(\.id), ["fan_0"])
    XCTAssertEqual(snapshot.channels.first?.label, "Fan 1")
    XCTAssertEqual(snapshot.summary, "CPU hotspot 54.2 °C")
  }

  func testGeneratedChineseResourceLocalizesRepresentativeDemoPayloads() async throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let stringsURL = projectRoot.appendingPathComponent(
      "Resources/zh-Hans.lproj/Localizable.strings"
    )
    let propertyList = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: stringsURL),
      format: nil
    )
    let strings = try XCTUnwrap(propertyList as? [String: String])
    let packagedLocalizer = SensorTextLocalizer(
      localize: { strings[$0] ?? $0 },
      locale: Locale(identifier: "zh-Hans")
    )

    var snapshots: [String: SensorSnapshot] = [:]
    for provider in SensorDemoProviderRegistry.providers() {
      let snapshot = await provider.read()
      snapshots[snapshot.id] = snapshot
    }

    let system = try XCTUnwrap(snapshots["system.overview"])
    XCTAssertEqual(packagedLocalizer.localized(system.name), "系统")
    XCTAssertEqual(
      packagedLocalizer.localized(system.summary),
      "Apple Silicon (demo) • 32 GB 内存"
    )
    XCTAssertEqual(
      packagedLocalizer.localized(try XCTUnwrap(system.channels.last).unit ?? ""),
      "小时"
    )

    let disk = try XCTUnwrap(snapshots["storage.disk_io"])
    XCTAssertEqual(packagedLocalizer.localized(disk.summary), "读取 18 MB/s • 写入 4 MB/s")
    XCTAssertEqual(
      packagedLocalizer.localized(
        "Compares aggregate read and write rates without exposing device identity"
      ),
      "对比汇总读写速率，不暴露设备身份"
    )

    XCTAssertEqual(
      packagedLocalizer.localized(
        "Compares aggregate receive and send rates without exposing interface identity"
      ),
      "对比汇总收发速率，不暴露接口身份"
    )

    let storage = try XCTUnwrap(snapshots["storage.system_volume"])
    XCTAssertEqual(
      packagedLocalizer.localized(
        try XCTUnwrap(storage.channels.first(where: { $0.id == "available_important" })).label
      ),
      "可用于重要用途"
    )

    let thermal = try XCTUnwrap(snapshots["thermal.pressure"])
    let thermalLevel = try XCTUnwrap(
      thermal.channels.first(where: { $0.id == "thermal_pressure_level" })
    )
    XCTAssertEqual(packagedLocalizer.localized(thermalLevel.label), "热压力等级")
    XCTAssertEqual(packagedLocalizer.localized(thermalLevel.formattedValue), "正常")
    XCTAssertEqual(packagedLocalizer.localized("Component Thermals"), "部件温度")
    XCTAssertEqual(packagedLocalizer.localized("System Power Trend"), "系统功耗趋势")

    let publicPower = try XCTUnwrap(snapshots["power.source"])
    XCTAssertEqual(packagedLocalizer.localized(publicPower.name), "系统电源来源")
    XCTAssertEqual(packagedLocalizer.localized(publicPower.summary), "78% • 电池")
    XCTAssertEqual(
      packagedLocalizer.localized(try XCTUnwrap(publicPower.channels.first).label),
      "当前供电来源"
    )
    let warning = try XCTUnwrap(
      publicPower.channels.first(where: { $0.id == "battery_warning" })
    )
    XCTAssertEqual(packagedLocalizer.localized(warning.label), "系统低电量告警")
    XCTAssertEqual(packagedLocalizer.localized(warning.formattedValue), "无告警")

    let display = try XCTUnwrap(snapshots["display.active"])
    XCTAssertEqual(packagedLocalizer.localized(display.summary), "3024 × 1964 px • 1 台活动显示器")
    XCTAssertEqual(
      packagedLocalizer.localized(
        try XCTUnwrap(display.channels.first(where: { $0.id == "main_resolution" })).label
      ),
      "主显示器像素尺寸"
    )
    XCTAssertEqual(
      packagedLocalizer.localized(
        try XCTUnwrap(display.channels.first(where: { $0.id == "main_logical_resolution" })).unit
          ?? ""
      ),
      "点"
    )
    XCTAssertEqual(
      String(
        format: try XCTUnwrap(
          strings[
            "Estimated from %lld samples over %@ minutes; workload changes can invalidate it."]
        ),
        locale: Locale(identifier: "zh-Hans"),
        arguments: [Int64(6), "5"]
      ),
      "依据 6 个样本（5 分钟）估算；工作负载变化可能使其失效。"
    )

    let motion = try XCTUnwrap(snapshots["motion.spu_live"])
    XCTAssertEqual(packagedLocalizer.localized(motion.summary), "实时加速度、水平与环境光数据")
    XCTAssertEqual(
      packagedLocalizer.localized(try XCTUnwrap(motion.channels.first).label),
      "加速度 X"
    )
    XCTAssertEqual(
      packagedLocalizer.localized(try XCTUnwrap(motion.notes.first)),
      "合成演示数据；并非硬件读数。"
    )

    let discovery = try XCTUnwrap(snapshots["motion.spu_discovery"])
    XCTAssertEqual(packagedLocalizer.localized(discovery.name), "Apple SPU 发现")
    XCTAssertEqual(
      packagedLocalizer.localized(try XCTUnwrap(discovery.channels.first).formattedValue),
      "已检测到"
    )

    XCTAssertEqual(system.summary, "Apple Silicon (demo) • 32 GB memory")
    XCTAssertEqual(motion.channels.first?.label, "Acceleration X")
  }

  func testOverviewHealthStateSeparatesLoadingFromReviewableIssues() {
    func snapshot(_ id: String, _ status: SensorStatus) -> SensorSnapshot {
      SensorSnapshot(
        id: id,
        name: "Fixture",
        category: .diagnostics,
        summary: "Fixture",
        status: status,
        source: "Fixture",
        capability: .publicAPI,
        channels: status == .available
          ? [SensorChannel(id: "value", label: "Value", formattedValue: "1")]
          : []
      )
    }

    let loading = ProviderHealthSummaryState(
      snapshots: [snapshot("loading", .loading)],
      samplingHealth: .empty
    )
    XCTAssertEqual(loading.metrics.map(\.status.rawValue), ["loading"])
    XCTAssertFalse(loading.hasReviewableIssues)
    XCTAssertEqual(loading.statusTransitionCount, 0)

    var tracker = SensorSamplingHealthTracker()
    _ = tracker.observe(
      snapshots: [snapshot("available", .permissionRequired)],
      cycleDuration: 0.1
    )
    let recoveredHealth = tracker.observe(
      snapshots: [snapshot("available", .available)],
      cycleDuration: 0.1
    )
    let mixed = ProviderHealthSummaryState(
      snapshots: [
        snapshot("available", .available),
        snapshot("limited", .degraded),
        snapshot("permission", .permissionRequired),
        snapshot("unavailable", .unavailable),
        snapshot("error", .error),
      ],
      samplingHealth: recoveredHealth
    )
    XCTAssertEqual(
      mixed.metrics.map(\.status.rawValue),
      ["available", "degraded", "permissionRequired", "unavailable", "error"]
    )
    XCTAssertEqual(mixed.metrics.map(\.count), [1, 1, 1, 1, 1])
    XCTAssertTrue(mixed.hasReviewableIssues)
    XCTAssertEqual(mixed.statusTransitionCount, 1)
  }
}
