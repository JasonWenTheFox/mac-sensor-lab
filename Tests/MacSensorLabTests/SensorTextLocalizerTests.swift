import Foundation
import XCTest

@testable import MacSensorLab
@testable import SensorCore

final class SensorTextLocalizerTests: XCTestCase {
  private let translations = [
    "%@ %@": "%@ %@",
    "%@ available": "可用空间 %@",
    "%@ • %@": "%@ • %@",
    "%@ • %@ memory": "%@ • %@ 内存",
    "%@ • %lld active": "%@ • %lld 台活动显示器",
    "%lld active displays": "%lld 台活动显示器",
    "%lld active • %lld EDR capable": "%lld 台活动显示器 • %lld 台支持 EDR",
    "%lld devices • %lld input • %lld output": "%lld 台设备 • %lld 台支持输入 • %lld 台支持输出",
    "%lld device • %lld input • %lld output": "%lld 台设备 • %lld 台支持输入 • %lld 台支持输出",
    "%lld audio device": "%lld 台音频设备",
    "%lld audio devices": "%lld 台音频设备",
    "%lld experimental sensor types detected": "检测到 %lld 类实验性传感器",
    "%lld of %lld capabilities detected": "已检测到 %lld/%lld 项能力",
    "%lld physical • %lld logical cores": "%lld 个物理核心 • %lld 个逻辑核心",
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
    "Display %lld %@": "显示器 %lld %@",
    "current pixels": "当前像素尺寸",
    "estimated pixel density": "估算像素密度",
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
    XCTAssertEqual(localizer.localized("1 audio device"), "1 台音频设备")
    XCTAssertEqual(
      localizer.localized("1 device • 0 input • 0 output"),
      "1 台设备 • 0 台支持输入 • 0 台支持输出"
    )
    XCTAssertEqual(localizer.localized("4 audio devices"), "4 台音频设备")
    XCTAssertEqual(
      localizer.localized("3 devices • 2 input • 2 output"),
      "3 台设备 • 2 台支持输入 • 2 台支持输出"
    )
    XCTAssertEqual(
      localizer.localized("2 active • 1 EDR capable"),
      "2 台活动显示器 • 1 台支持 EDR"
    )
    XCTAssertEqual(
      localizer.localized("Display 2 estimated pixel density"),
      "显示器 2 估算像素密度"
    )
    XCTAssertEqual(localizer.localized("CPU 38%"), "CPU 38%")
    XCTAssertEqual(
      localizer.localized("10 physical • 10 logical cores"),
      "10 个物理核心 • 10 个逻辑核心"
    )
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
    XCTAssertEqual(
      packagedLocalizer.localized(motion.summary),
      "加速度、水平与环境光演示数据"
    )
    XCTAssertEqual(
      packagedLocalizer.localized(try XCTUnwrap(motion.channels.first).label),
      "加速度 X"
    )
    XCTAssertEqual(
      packagedLocalizer.localized(try XCTUnwrap(motion.notes.first)),
      "合成演示数据；并非硬件读数。"
    )

    let discovery = try XCTUnwrap(snapshots["motion.spu_discovery"])
    XCTAssertEqual(packagedLocalizer.localized(discovery.name), "Apple SPU 传感器")
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

@MainActor
final class SensorDashboardModelTests: XCTestCase {
  func testSlowProviderCannotFreezeTheWholeRefreshCycle() async {
    let slow = SlowDashboardProvider()
    let fast = FastDashboardProvider()
    let model = SensorDashboardModel(
      providers: [slow, fast],
      isDemoMode: true,
      providerReadTimeout: .milliseconds(20)
    )
    let clock = ContinuousClock()
    let startedAt = clock.now

    await model.refresh()

    XCTAssertLessThan(startedAt.duration(to: clock.now), .milliseconds(100))
    XCTAssertFalse(model.isRefreshing)
    XCTAssertEqual(model.samplingHealth.completedCycleCount, 1)
    XCTAssertEqual(model.snapshots.first(where: { $0.id == "test.slow" })?.status, .degraded)
    XCTAssertEqual(model.snapshots.first(where: { $0.id == "test.fast" })?.status, .available)
  }

  func testDisplayRulerModelCalibratesAndPreservesAValidResultAfterBadInput() throws {
    let mode = try XCTUnwrap(
      DisplayCalibrationModeSignature(
        pixelWidth: 3_024,
        pixelHeight: 1_964,
        pointWidth: 1_512,
        pointHeight: 982,
        rotationDegrees: 0
      )
    )
    let session = DisplayCalibrationSession()
    XCTAssertEqual(
      session.synchronize(
        observations: [
          DisplayCalibrationObservation(
            identity: DisplayCalibrationDisplayIdentity(rawValue: 101),
            mode: mode
          )
        ]
      ),
      .topologyChanged
    )
    let model = DisplayRulerModel(session: session)
    model.updateCurrentContext(try XCTUnwrap(session.context(forSlotIndex: 1)))
    XCTAssertEqual(model.status, .ready)

    model.referenceMillimeters = 100
    model.calibrate(renderedPoints: 500)
    let validMeasurement = try XCTUnwrap(model.measurement)
    XCTAssertEqual(model.status, .calibrated)
    XCTAssertEqual(validMeasurement.horizontalPixelsPerInch, 254, accuracy: 0.000_001)

    model.referenceMillimeters = 5
    model.calibrate(renderedPoints: 500)
    XCTAssertEqual(model.status, .invalidInput)
    XCTAssertEqual(model.measurement, validMeasurement)

    model.clearCalibration()
    XCTAssertEqual(model.status, .ready)
    XCTAssertNil(model.measurement)
  }

  func testDisplayRulerModelSwitchesScreensWithoutInvalidatingTheirSessionCalibration() throws {
    let modeA = try XCTUnwrap(
      DisplayCalibrationModeSignature(
        pixelWidth: 3_024,
        pixelHeight: 1_964,
        pointWidth: 1_512,
        pointHeight: 982,
        rotationDegrees: 0
      )
    )
    let modeB = try XCTUnwrap(
      DisplayCalibrationModeSignature(
        pixelWidth: 2_560,
        pixelHeight: 1_600,
        pointWidth: 1_280,
        pointHeight: 800,
        rotationDegrees: 0
      )
    )
    let displayA = DisplayCalibrationDisplayIdentity(rawValue: 101)
    let displayB = DisplayCalibrationDisplayIdentity(rawValue: 202)
    let session = DisplayCalibrationSession()
    _ = session.synchronize(
      observations: [
        DisplayCalibrationObservation(identity: displayA, mode: modeA),
        DisplayCalibrationObservation(identity: displayB, mode: modeB),
      ]
    )
    let contextA = try XCTUnwrap(session.context(forSlotIndex: 1))
    let contextB = try XCTUnwrap(session.context(forSlotIndex: 2))
    let model = DisplayRulerModel(session: session)

    model.updateCurrentContext(contextA)
    model.referenceMillimeters = 100
    model.calibrate(renderedPoints: 500)
    let measurementA = try XCTUnwrap(model.measurement)

    model.updateCurrentContext(contextB)
    XCTAssertEqual(model.status, .ready)
    XCTAssertNil(model.measurement)
    XCTAssertEqual(session.calibration(for: contextA), measurementA)

    model.updateCurrentContext(contextA)
    XCTAssertEqual(model.status, .calibrated)
    XCTAssertEqual(model.measurement, measurementA)

    XCTAssertEqual(
      session.synchronize(
        observations: [
          DisplayCalibrationObservation(identity: displayA, mode: modeB),
          DisplayCalibrationObservation(identity: displayB, mode: modeB),
        ]
      ),
      .modeChanged(slotIndices: [1])
    )
    model.updateCurrentContext(try XCTUnwrap(session.context(forSlotIndex: 1)))
    XCTAssertEqual(model.status, .invalidated)
    XCTAssertNil(model.measurement)
  }

  func testDisplayRulerLayoutAndSystemEstimateRespectVisibleAndRotatedAxes() throws {
    XCTAssertEqual(
      DisplayRulerLayout.maximumRenderedPoints(availableWidth: 1_000),
      600,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      DisplayRulerLayout.renderedPoints(requested: 500, availableWidth: 300),
      284,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      DisplayRulerLayout.renderedPoints(requested: .nan, availableWidth: 300),
      20,
      accuracy: 0.000_001
    )

    let rotatedMode = try XCTUnwrap(
      DisplayCalibrationModeSignature.currentAxes(
        pixelWidth: 3_024,
        pixelHeight: 1_964,
        pointWidth: 1_512,
        pointHeight: 982,
        rotationDegrees: 90
      )
    )
    let systemEstimate = try XCTUnwrap(
      DisplayCalibrationSystemEstimate.currentHorizontalAxis(
        physicalWidthMillimeters: 286,
        physicalHeightMillimeters: 186,
        mode: rotatedMode
      )
    )
    XCTAssertEqual(systemEstimate.horizontalSpanMillimeters, 186, accuracy: 0.000_001)
    XCTAssertEqual(
      systemEstimate.horizontalPixelsPerInch,
      Double(rotatedMode.pixelWidth) * 25.4 / 186,
      accuracy: 0.000_001
    )

    let session = DisplayCalibrationSession()
    _ = session.synchronize(
      observations: [
        DisplayCalibrationObservation(
          identity: DisplayCalibrationDisplayIdentity(rawValue: 303),
          mode: rotatedMode,
          systemEstimate: systemEstimate
        )
      ]
    )
    let context = try XCTUnwrap(session.context(forSlotIndex: 1))
    let model = DisplayRulerModel(session: session)
    model.updateCurrentContext(context)
    XCTAssertEqual(model.systemEstimate, systemEstimate)
  }

  func testPressureLabTracksStageLocalSamplesAndForceClickTransitions() throws {
    let model = PressureLabModel()
    model.start(at: 100)
    XCTAssertTrue(model.isCapturing)
    XCTAssertEqual(model.status, .waiting)

    model.observeInputCapability(false)
    XCTAssertEqual(model.status, .unsupportedInput)
    model.observeInputCapability(true)
    XCTAssertEqual(model.status, .waiting)

    XCTAssertTrue(
      model.record(
        try XCTUnwrap(
          PressureLabEventInput(
            timestamp: 100.1,
            normalizedPressure: 0.25,
            stage: 1,
            stageTransition: 0
          )
        )
      )
    )
    XCTAssertTrue(
      model.record(
        try XCTUnwrap(
          PressureLabEventInput(
            timestamp: 100.2,
            normalizedPressure: 0.85,
            stage: 1,
            stageTransition: 0.7
          )
        )
      )
    )
    XCTAssertTrue(
      model.record(
        try XCTUnwrap(
          PressureLabEventInput(
            timestamp: 100.3,
            normalizedPressure: 0.1,
            stage: 2,
            stageTransition: 0
          )
        )
      )
    )
    XCTAssertTrue(
      model.record(
        try XCTUnwrap(
          PressureLabEventInput(
            timestamp: 100.4,
            normalizedPressure: 0.4,
            stage: 2,
            stageTransition: -0.5
          )
        )
      )
    )
    XCTAssertTrue(
      model.record(
        try XCTUnwrap(
          PressureLabEventInput(
            timestamp: 100.5,
            normalizedPressure: 0.2,
            stage: 1,
            stageTransition: 0
          )
        )
      )
    )

    XCTAssertEqual(model.status, .receiving)
    XCTAssertEqual(model.forceClickTransitionCount, 1)
    XCTAssertEqual(model.samples.map(\.segmentID), [1, 1, 2, 2, 3])
    XCTAssertEqual(model.latestSample?.stage, 1)
    XCTAssertEqual(
      try XCTUnwrap(model.peakNormalizedPressureForCurrentStage),
      0.2,
      accuracy: 0.000_001
    )

    model.stop()
    XCTAssertFalse(model.isCapturing)
    XCTAssertEqual(model.status, .stopped)
    XCTAssertEqual(model.samples.count, 5)

    model.leaveExperiment()
    XCTAssertEqual(model.status, .idle)
    XCTAssertTrue(model.samples.isEmpty)
    XCTAssertNil(model.inputSupportsPressure)
  }

  func testPressureLabRejectsMalformedOrOutOfOrderEvents() throws {
    let model = PressureLabModel()
    let valid = try XCTUnwrap(
      PressureLabEventInput(
        timestamp: 10,
        normalizedPressure: 0.5,
        stage: 1,
        stageTransition: 0
      )
    )
    XCTAssertFalse(model.record(valid))

    model.start(at: .nan)
    XCTAssertFalse(model.isCapturing)
    XCTAssertEqual(model.status, .idle)

    model.start(at: 10)
    XCTAssertNil(
      PressureLabEventInput(
        timestamp: 10,
        normalizedPressure: 1.01,
        stage: 1,
        stageTransition: 0
      )
    )
    XCTAssertNil(
      PressureLabEventInput(
        timestamp: 10,
        normalizedPressure: 0.5,
        stage: 3,
        stageTransition: 0
      )
    )
    XCTAssertNil(
      PressureLabEventInput(
        timestamp: 10,
        normalizedPressure: 0.5,
        stage: 1,
        stageTransition: -.infinity
      )
    )
    XCTAssertFalse(
      model.record(
        try XCTUnwrap(
          PressureLabEventInput(
            timestamp: 9.99,
            normalizedPressure: 0.5,
            stage: 1,
            stageTransition: 0
          )
        )
      )
    )
    XCTAssertTrue(model.record(valid))
    XCTAssertFalse(
      model.record(
        try XCTUnwrap(
          PressureLabEventInput(
            timestamp: 9.999,
            normalizedPressure: 0.6,
            stage: 1,
            stageTransition: 0
          )
        )
      )
    )
    XCTAssertEqual(model.samples.count, 1)
  }

  func testPressureLabBoundsRetainedHistory() throws {
    let model = PressureLabModel()
    model.start(at: 1_000)

    for index in 0..<300 {
      XCTAssertTrue(
        model.record(
          try XCTUnwrap(
            PressureLabEventInput(
              timestamp: 1_000 + Double(index) / 100,
              normalizedPressure: Double(index % 101) / 100,
              stage: 1,
              stageTransition: 0
            )
          )
        )
      )
    }

    XCTAssertEqual(model.samples.count, PressureLabModel.maximumSampleCount)
    XCTAssertEqual(model.samples.first?.id, 61)
    XCTAssertEqual(model.samples.last?.id, 300)
    XCTAssertEqual(model.samples.first?.segmentID, 1)
    XCTAssertEqual(model.forceClickTransitionCount, 0)
  }

  func testMicrophoneInputRequiresConfirmationBeforePermissionAndCapture() async throws {
    let authorization = MicrophoneAuthorizationFixture(state: .notDetermined)
    authorization.requestResult = .authorized
    let capture = FixtureMicrophoneCaptureSession()
    let model = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: capture,
      maximumSessionDuration: .seconds(1)
    )

    model.beginStart()
    XCTAssertEqual(model.status, .awaitingPermissionConfirmation)
    XCTAssertEqual(authorization.requestCount, 0)
    XCTAssertEqual(capture.startCount, 0)

    model.confirmPermissionAndStart()
    await waitUntil { model.status == .capturing }
    XCTAssertEqual(authorization.requestCount, 1)
    XCTAssertEqual(capture.startCount, 1)
    XCTAssertEqual(model.authorizationState, .authorized)

    capture.emit(frameCount: 1_024, sampleRate: 48_000, channelCount: 2)
    await waitUntil { model.observationCount == 1 }
    XCTAssertEqual(model.totalFrameCount, 1_024)
    XCTAssertEqual(model.format, MicrophonePCMFormatMetadata(sampleRate: 48_000, channelCount: 2))
    XCTAssertEqual(model.latestAnalysis, microphoneAnalysisFixture())
    XCTAssertEqual(model.levelHistory.count, 1)

    model.stop()
    XCTAssertEqual(model.status, .stopped)
    XCTAssertEqual(capture.stopCount, 1)
    XCTAssertEqual(model.totalFrameCount, 1_024)

    model.leaveExperiment()
    XCTAssertEqual(model.status, .idle)
    XCTAssertNil(model.format)
    XCTAssertEqual(model.observationCount, 0)
    XCTAssertEqual(model.totalFrameCount, 0)
    XCTAssertNil(model.latestAnalysis)
    XCTAssertTrue(model.levelHistory.isEmpty)
  }

  func testMicrophoneInputDeniedAndRestrictedStatesNeverStartCapture() {
    for permission in [MicrophoneAuthorizationState.denied, .restricted] {
      let authorization = MicrophoneAuthorizationFixture(state: permission)
      let capture = FixtureMicrophoneCaptureSession()
      let model = MicrophoneInputModel(
        authorizationClient: authorization.client,
        captureSession: capture
      )

      model.beginStart()

      XCTAssertEqual(
        model.status,
        permission == .denied ? .permissionDenied : .permissionRestricted
      )
      XCTAssertEqual(authorization.requestCount, 0)
      XCTAssertEqual(capture.startCount, 0)
      XCTAssertFalse(model.canStart)
    }
  }

  func testMicrophoneInputIncompletePermissionRequestFailsWithoutInventingDenial() async {
    let authorization = MicrophoneAuthorizationFixture(state: .notDetermined)
    authorization.requestResult = .notDetermined
    let capture = FixtureMicrophoneCaptureSession()
    let model = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: capture
    )

    model.beginStart()
    model.confirmPermissionAndStart()
    await waitUntil { model.status == .failed(.permissionRequestIncomplete) }

    XCTAssertEqual(model.authorizationState, .notDetermined)
    XCTAssertEqual(capture.startCount, 0)
  }

  func testMicrophoneInputLeavingDuringPermissionRequestCannotStartLateCapture() async {
    let authorization = MicrophoneAuthorizationFixture(state: .notDetermined)
    authorization.requestResult = .authorized
    authorization.requestDelay = .milliseconds(30)
    let capture = FixtureMicrophoneCaptureSession()
    let model = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: capture
    )

    model.beginStart()
    model.confirmPermissionAndStart()
    XCTAssertEqual(model.status, .requestingPermission)
    model.leaveExperiment()
    XCTAssertEqual(model.status, .idle)

    try? await Task.sleep(for: .milliseconds(60))
    XCTAssertEqual(capture.startCount, 0)
    XCTAssertEqual(model.status, .idle)
  }

  func testMicrophoneInputStopsForFormatChangeAndIgnoresLateBuffers() async {
    let authorization = MicrophoneAuthorizationFixture(state: .authorized)
    let capture = FixtureMicrophoneCaptureSession()
    let model = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: capture
    )

    model.beginStart()
    XCTAssertEqual(model.status, .capturing)
    capture.emit(frameCount: 512, sampleRate: 48_000, channelCount: 2)
    await waitUntil { model.observationCount == 1 }
    capture.emit(frameCount: 512, sampleRate: 44_100, channelCount: 2)
    await waitUntil { model.status == .interrupted(.configurationChanged) }

    XCTAssertEqual(capture.stopCount, 1)
    XCTAssertEqual(model.totalFrameCount, 512)
    capture.emitLate(frameCount: 512, sampleRate: 48_000, channelCount: 2)
    await Task.yield()
    XCTAssertEqual(model.totalFrameCount, 512)
  }

  func testMicrophoneInputStopsAtDurationAndLifecycleTermination() async {
    let authorization = MicrophoneAuthorizationFixture(state: .authorized)
    let timedCapture = FixtureMicrophoneCaptureSession()
    let timedModel = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: timedCapture,
      maximumSessionDuration: .milliseconds(10)
    )

    timedModel.beginStart()
    await waitUntil { timedModel.status == .sessionLimitReached }
    XCTAssertEqual(timedCapture.stopCount, 1)

    let interruptedCapture = FixtureMicrophoneCaptureSession()
    let interruptedModel = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: interruptedCapture
    )
    interruptedModel.beginStart()
    interruptedCapture.terminate(.systemSleep)
    await waitUntil { interruptedModel.status == .interrupted(.systemSleep) }
    XCTAssertEqual(interruptedCapture.stopCount, 1)
  }

  func testMicrophoneInputValidationAndStartFailuresFailClosed() {
    XCTAssertNil(MicrophonePCMFormatMetadata(sampleRate: 0, channelCount: 2))
    XCTAssertNil(MicrophonePCMFormatMetadata(sampleRate: .nan, channelCount: 2))
    XCTAssertNil(MicrophonePCMFormatMetadata(sampleRate: 48_000, channelCount: 0))
    XCTAssertNil(
      MicrophonePCMObservation(
        frameCount: 0,
        sampleRate: 48_000,
        channelCount: 2,
        analysis: microphoneAnalysisFixture()
      )
    )
    XCTAssertNil(
      MicrophonePCMObservation(
        frameCount: MicrophonePCMObservation.maximumFrameCount + 1,
        sampleRate: 48_000,
        channelCount: 2,
        analysis: microphoneAnalysisFixture()
      )
    )

    let authorization = MicrophoneAuthorizationFixture(state: .authorized)
    let unavailableCapture = FixtureMicrophoneCaptureSession()
    unavailableCapture.startError = .inputUnavailable
    let unavailableModel = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: unavailableCapture
    )
    unavailableModel.beginStart()
    XCTAssertEqual(unavailableModel.status, .failed(.inputUnavailable))

    let failedCapture = FixtureMicrophoneCaptureSession()
    failedCapture.startError = .startFailed
    let failedModel = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: failedCapture
    )
    failedModel.beginStart()
    XCTAssertEqual(failedModel.status, .failed(.startFailed))
    XCTAssertGreaterThanOrEqual(failedCapture.stopCount, 1)
  }

  func testDemoMicrophoneInputProducesOnlyBoundedMetadataAndClearsOnLeave() async {
    let model = MicrophoneInputModel(isDemoMode: true)
    XCTAssertEqual(model.authorizationState, .authorized)

    model.beginStart()
    XCTAssertEqual(model.status, .capturing)
    await waitUntil(timeout: .seconds(1)) { model.observationCount > 0 }
    XCTAssertGreaterThan(model.totalFrameCount, 0)
    XCTAssertEqual(model.format?.sampleRate, 48_000)
    XCTAssertEqual(model.format?.channelCount, 2)
    XCTAssertNotNil(model.latestAnalysis)
    XCTAssertNotNil(model.latestSpectrum)
    XCTAssertFalse(model.levelHistory.isEmpty)

    model.leaveExperiment()
    XCTAssertEqual(model.status, .idle)
    XCTAssertNil(model.format)
    XCTAssertEqual(model.totalFrameCount, 0)
    XCTAssertNil(model.latestAnalysis)
    XCTAssertNil(model.latestSpectrum)
    XCTAssertTrue(model.levelHistory.isEmpty)
  }

  func testCameraFrameAnalyzerReducesBGRAWithoutRetainingPixels() throws {
    let analysis = try XCTUnwrap(
      CameraFrameAnalyzer.analyzeBGRA(
        width: 2,
        height: 1,
        bytesPerRow: 8,
        bytes: [
          0, 0, 0, 255,
          255, 255, 255, 255,
        ]
      )
    )

    XCTAssertEqual(analysis.sampledPixelCount, 2)
    XCTAssertEqual(analysis.minimumRelativeLuma, 0, accuracy: 1e-12)
    XCTAssertEqual(analysis.meanRelativeLuma, 0.5, accuracy: 1e-12)
    XCTAssertEqual(analysis.maximumRelativeLuma, 1, accuracy: 1e-12)
    XCTAssertEqual(analysis.sampledContrastSpan, 1, accuracy: 1e-12)

    let bounded = try XCTUnwrap(
      CameraFrameAnalyzer.analyzeBGRA(
        width: 128,
        height: 128,
        bytesPerRow: 512,
        bytes: Array(repeating: 64, count: 65_536)
      )
    )
    XCTAssertLessThanOrEqual(
      bounded.sampledPixelCount,
      CameraFrameAnalyzer.maximumSampledPixelCount
    )
    XCTAssertEqual(bounded.meanRelativeLuma, 64.0 / 255, accuracy: 1e-12)
  }

  func testCameraFrameAnalyzerRejectsMalformedOrOverLimitBuffers() {
    XCTAssertNil(
      CameraFrameAnalyzer.analyzeBGRA(
        width: 0,
        height: 1,
        bytesPerRow: 4,
        bytes: [0, 0, 0, 255]
      )
    )
    XCTAssertNil(
      CameraFrameAnalyzer.analyzeBGRA(
        width: 2,
        height: 1,
        bytesPerRow: 4,
        bytes: Array(repeating: 0, count: 8)
      )
    )
    XCTAssertNil(
      CameraFrameAnalyzer.analyzeBGRA(
        width: 2,
        height: 2,
        bytesPerRow: 8,
        bytes: Array(repeating: 0, count: 15)
      )
    )
    XCTAssertNil(
      CameraFrameAnalyzer.analyzeBGRA(
        width: CameraFrameAnalyzer.maximumDimension + 1,
        height: 1,
        bytesPerRow: 4,
        bytes: [0, 0, 0, 255]
      )
    )
  }

  func testCameraCheckAlwaysRequiresLiveConfirmationBeforeCapture() async {
    let authorization = CameraAuthorizationFixture(state: .authorized)
    let capture = FixtureCameraCaptureSession()
    let model = CameraCheckModel(
      authorizationClient: authorization.client,
      captureSession: capture,
      maximumSessionDuration: .seconds(1)
    )

    model.beginStart()
    XCTAssertEqual(model.status, .awaitingPermissionConfirmation)
    XCTAssertEqual(authorization.requestCount, 0)
    XCTAssertEqual(capture.startCount, 0)

    model.confirmPermissionAndStart()
    await waitUntil { model.status == .capturing }
    XCTAssertEqual(authorization.requestCount, 0)
    XCTAssertEqual(capture.startCount, 1)

    capture.emit(cameraObservation(delivered: 3, time: 1))
    await waitUntil { model.analyzedObservationCount == 1 }
    XCTAssertEqual(model.latestObservation?.width, 1_280)
    XCTAssertNil(model.observedDeliveryFrameRate)

    capture.emit(cameraObservation(delivered: 6, time: 1.1))
    await waitUntil { model.analyzedObservationCount == 2 }
    XCTAssertEqual(model.observedDeliveryFrameRate ?? 0, 30, accuracy: 1e-8)

    model.stop()
    XCTAssertEqual(model.status, .stopped)
    XCTAssertEqual(capture.stopCount, 1)
    XCTAssertNotNil(model.latestObservation)

    model.leaveExperiment()
    XCTAssertEqual(model.status, .idle)
    XCTAssertNil(model.latestObservation)
    XCTAssertEqual(model.analyzedObservationCount, 0)
    XCTAssertNil(model.observedDeliveryFrameRate)
  }

  func testCameraCheckRequestsPermissionOnlyAfterSecondAction() async {
    let authorization = CameraAuthorizationFixture(state: .notDetermined)
    authorization.requestResult = .authorized
    let capture = FixtureCameraCaptureSession()
    let model = CameraCheckModel(
      authorizationClient: authorization.client,
      captureSession: capture
    )

    model.beginStart()
    XCTAssertEqual(model.status, .awaitingPermissionConfirmation)
    XCTAssertEqual(authorization.requestCount, 0)
    model.confirmPermissionAndStart()
    await waitUntil { model.status == .capturing }

    XCTAssertEqual(authorization.requestCount, 1)
    XCTAssertEqual(model.authorizationState, .authorized)
    XCTAssertEqual(capture.startCount, 1)
    model.leaveExperiment()
  }

  func testCameraCheckDeniedRestrictedAndIncompletePermissionFailClosed() async {
    for permission in [CameraAuthorizationState.denied, .restricted] {
      let authorization = CameraAuthorizationFixture(state: permission)
      let capture = FixtureCameraCaptureSession()
      let model = CameraCheckModel(
        authorizationClient: authorization.client,
        captureSession: capture
      )

      model.beginStart()
      XCTAssertEqual(
        model.status,
        permission == .denied ? .permissionDenied : .permissionRestricted
      )
      XCTAssertEqual(capture.startCount, 0)
      XCTAssertFalse(model.canStart)
    }

    let incompleteAuthorization = CameraAuthorizationFixture(state: .notDetermined)
    incompleteAuthorization.requestResult = .notDetermined
    let incompleteCapture = FixtureCameraCaptureSession()
    let incompleteModel = CameraCheckModel(
      authorizationClient: incompleteAuthorization.client,
      captureSession: incompleteCapture
    )
    incompleteModel.beginStart()
    incompleteModel.confirmPermissionAndStart()
    await waitUntil {
      incompleteModel.status == .failed(.permissionRequestIncomplete)
    }
    XCTAssertEqual(incompleteCapture.startCount, 0)
  }

  func testCameraCheckLeaveRejectsLatePermissionAndFrameCallbacks() async {
    let authorization = CameraAuthorizationFixture(state: .notDetermined)
    authorization.requestResult = .authorized
    authorization.requestDelay = .milliseconds(30)
    let capture = FixtureCameraCaptureSession()
    let model = CameraCheckModel(
      authorizationClient: authorization.client,
      captureSession: capture
    )

    model.beginStart()
    model.confirmPermissionAndStart()
    XCTAssertEqual(model.status, .requestingPermission)
    model.leaveExperiment()
    try? await Task.sleep(for: .milliseconds(60))
    XCTAssertEqual(capture.startCount, 0)
    XCTAssertEqual(model.status, .idle)

    let authorized = CameraAuthorizationFixture(state: .authorized)
    let activeCapture = FixtureCameraCaptureSession()
    let activeModel = CameraCheckModel(
      authorizationClient: authorized.client,
      captureSession: activeCapture
    )
    activeModel.beginStart()
    activeModel.confirmPermissionAndStart()
    await waitUntil { activeModel.status == .capturing }
    activeCapture.emit(cameraObservation(delivered: 1, time: 1))
    await waitUntil { activeModel.analyzedObservationCount == 1 }
    activeModel.leaveExperiment()
    activeCapture.emitLate(cameraObservation(delivered: 2, time: 1.1))
    await Task.yield()
    XCTAssertEqual(activeModel.analyzedObservationCount, 0)
    XCTAssertNil(activeModel.latestObservation)
  }

  func testCameraCheckStopsAtDurationLifecycleAndMalformedSequence() async {
    let authorization = CameraAuthorizationFixture(state: .authorized)
    let timedCapture = FixtureCameraCaptureSession()
    let timedModel = CameraCheckModel(
      authorizationClient: authorization.client,
      captureSession: timedCapture,
      maximumSessionDuration: .milliseconds(10)
    )
    timedModel.beginStart()
    timedModel.confirmPermissionAndStart()
    await waitUntil { timedModel.status == .sessionLimitReached }
    XCTAssertEqual(timedCapture.stopCount, 1)

    let interruptedCapture = FixtureCameraCaptureSession()
    let interruptedModel = CameraCheckModel(
      authorizationClient: authorization.client,
      captureSession: interruptedCapture
    )
    interruptedModel.beginStart()
    interruptedModel.confirmPermissionAndStart()
    await waitUntil { interruptedModel.status == .capturing }
    interruptedCapture.terminate(.systemSleep)
    await waitUntil { interruptedModel.status == .interrupted(.systemSleep) }
    XCTAssertEqual(interruptedCapture.stopCount, 1)

    let malformedCapture = FixtureCameraCaptureSession()
    let malformedModel = CameraCheckModel(
      authorizationClient: authorization.client,
      captureSession: malformedCapture
    )
    malformedModel.beginStart()
    malformedModel.confirmPermissionAndStart()
    await waitUntil { malformedModel.status == .capturing }
    malformedCapture.emit(cameraObservation(delivered: 3, time: 1))
    await waitUntil { malformedModel.analyzedObservationCount == 1 }
    malformedCapture.emit(cameraObservation(delivered: 3, time: 1.1))
    await waitUntil { malformedModel.status == .interrupted(.invalidFrame) }
    XCTAssertEqual(malformedCapture.stopCount, 1)
  }

  func testCameraCheckStartFailuresAndDemoStayBounded() async {
    let authorization = CameraAuthorizationFixture(state: .authorized)
    for (error, failure) in [
      (CameraCaptureSessionError.noSupportedLocalCamera, CameraCheckFailure.noSupportedLocalCamera),
      (CameraCaptureSessionError.configurationFailed, CameraCheckFailure.configurationFailed),
      (
        CameraCaptureSessionError.continuityBoundaryMissing,
        CameraCheckFailure.continuityBoundaryMissing
      ),
    ] {
      let capture = FixtureCameraCaptureSession()
      capture.startError = error
      let model = CameraCheckModel(
        authorizationClient: authorization.client,
        captureSession: capture
      )
      model.beginStart()
      model.confirmPermissionAndStart()
      XCTAssertEqual(model.status, .failed(failure))
      XCTAssertGreaterThanOrEqual(capture.stopCount, 1)
    }

    let startCapture = FixtureCameraCaptureSession()
    startCapture.startsSuccessfully = false
    let startModel = CameraCheckModel(
      authorizationClient: authorization.client,
      captureSession: startCapture
    )
    startModel.beginStart()
    startModel.confirmPermissionAndStart()
    await waitUntil { startModel.status == .failed(.startFailed) }

    let demoModel = CameraCheckModel(isDemoMode: true)
    demoModel.beginStart()
    await waitUntil { demoModel.status == .capturing }
    await waitUntil(timeout: .seconds(1)) { demoModel.latestObservation != nil }
    XCTAssertEqual(demoModel.authorizationState, .authorized)
    XCTAssertLessThanOrEqual(
      demoModel.latestObservation?.analysis.sampledPixelCount ?? .max,
      CameraFrameAnalyzer.maximumSampledPixelCount
    )
    demoModel.leaveExperiment()
    XCTAssertEqual(demoModel.status, .idle)
    XCTAssertNil(demoModel.latestObservation)
  }

  func testCameraCheckSourceUsesOnlyReviewedCaptureAndReductionPaths() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let captureSource = try String(
      contentsOf: projectRoot.appendingPathComponent(
        "Sources/MacSensorLab/CameraCheckView.swift"
      ),
      encoding: .utf8
    )
    let analysisSource = try String(
      contentsOf: projectRoot.appendingPathComponent(
        "Sources/MacSensorLab/CameraFrameAnalysis.swift"
      ),
      encoding: .utf8
    )

    for required in [
      "AVCaptureDevice.authorizationStatus(for: .video)",
      "AVCaptureDevice.requestAccess(for: .video)",
      "AVCaptureDevice.DiscoverySession", ".builtInWideAngleCamera", ".external",
      "AVCaptureDeviceInput(device:", "AVCaptureSession()", "AVCaptureVideoDataOutput()",
      "alwaysDiscardsLateVideoFrames = true", "kCVPixelFormatType_32BGRA",
      "defaultMaximumSessionDuration: Duration = .seconds(120)",
    ] {
      XCTAssertTrue(captureSource.contains(required), "Missing Camera Check path: \(required)")
    }
    XCTAssertTrue(analysisSource.contains("maximumSampledPixelCount = 4_096"))

    for forbidden in [
      "uniqueID", "modelID", "localizedName", "manufacturer", "linkedDevices",
      "constituentDevices", "userPreferredCamera", "systemPreferredCamera", "defaultDevice",
      "PhotoOutput", "MovieFileOutput", "MetadataOutput", "AudioDataOutput",
      "AVAssetWriter", "lockForConfiguration", "activeFormat",
      "isInUseByAnotherApplication", "isSuspended", "CGImageDestination", "CIContext",
      "VNDetect", "VNRecognize", "URLSession",
    ] {
      XCTAssertFalse(captureSource.contains(forbidden), "Forbidden Camera Check path: \(forbidden)")
    }
  }

  func testMicrophonePCMAnalysisCalculatesRMSPeakAndDBFS() throws {
    let analysis = try XCTUnwrap(
      MicrophonePCMAnalyzer.analyze(channels: [[0, 1, 0, -1]])
    )

    XCTAssertEqual(analysis.rootMeanSquareAmplitude, sqrt(0.5), accuracy: 0.000_001)
    XCTAssertEqual(analysis.peakAmplitude, 1, accuracy: 0.000_001)
    XCTAssertEqual(
      try XCTUnwrap(analysis.rootMeanSquareDBFS),
      -3.010_299_956,
      accuracy: 0.000_001
    )
    XCTAssertEqual(try XCTUnwrap(analysis.peakDBFS), 0, accuracy: 0.000_001)
    XCTAssertEqual(analysis.waveform.count, 4)
    XCTAssertEqual(analysis.waveform.map(\.minimum), [0, 1, 0, -1])
    XCTAssertEqual(analysis.waveform.map(\.maximum), [0, 1, 0, -1])
  }

  func testMicrophonePCMAnalysisKeepsMultichannelEnergyWithoutWaveformCancellation() throws {
    let analysis = try XCTUnwrap(
      MicrophonePCMAnalyzer.analyze(channels: [[1, -1], [-1, 1]])
    )

    XCTAssertEqual(analysis.rootMeanSquareAmplitude, 1, accuracy: 0.000_001)
    XCTAssertEqual(analysis.peakAmplitude, 1, accuracy: 0.000_001)
    XCTAssertTrue(analysis.waveform.allSatisfy { $0.minimum == 0 && $0.maximum == 0 })
  }

  func testMicrophonePCMAnalysisRepresentsSilenceWithoutInventingFiniteDBFS() throws {
    let analysis = try XCTUnwrap(
      MicrophonePCMAnalyzer.analyze(channels: [Array(repeating: 0, count: 32)])
    )
    let level = try XCTUnwrap(
      MicrophoneLevelPoint(id: 1, elapsedSeconds: 0.1, analysis: analysis)
    )

    XCTAssertEqual(analysis.rootMeanSquareAmplitude, 0)
    XCTAssertEqual(analysis.peakAmplitude, 0)
    XCTAssertNil(analysis.rootMeanSquareDBFS)
    XCTAssertNil(analysis.peakDBFS)
    XCTAssertEqual(level.rootMeanSquareDBFS, MicrophoneLevelPoint.displayFloorDBFS)
    XCTAssertEqual(level.peakDBFS, MicrophoneLevelPoint.displayFloorDBFS)
  }

  func testMicrophonePCMAnalysisRejectsMalformedOrUnboundedInput() {
    XCTAssertNil(MicrophonePCMAnalyzer.analyze(channels: []))
    XCTAssertNil(MicrophonePCMAnalyzer.analyze(channels: [[]]))
    XCTAssertNil(MicrophonePCMAnalyzer.analyze(channels: [[0], [0, 1]]))
    XCTAssertNil(MicrophonePCMAnalyzer.analyze(channels: [[.nan]]))
    XCTAssertNil(MicrophonePCMAnalyzer.analyze(channels: [[.infinity]]))
    XCTAssertNil(
      MicrophonePCMAnalyzer.analyze(
        channels: [[Float(MicrophonePCMAnalyzer.maximumAbsoluteSample + 1)]]
      )
    )
    XCTAssertNil(
      MicrophonePCMAnalyzer.analyze(
        channels: Array(
          repeating: [Float.zero],
          count: MicrophonePCMAnalyzer.maximumChannelCount + 1
        )
      )
    )
    XCTAssertNil(
      MicrophonePCMAnalyzer.analyze(
        channels: [
          Array(
            repeating: 0,
            count: MicrophonePCMAnalyzer.maximumFrameCount + 1
          )
        ]
      )
    )
    XCTAssertNil(
      MicrophonePCMAnalyzer.analyze(
        channels: Array(
          repeating: Array(repeating: 0, count: 4_097),
          count: MicrophonePCMAnalyzer.maximumChannelCount
        )
      )
    )
  }

  func testMicrophonePCMAnalysisBoundsWaveformAndLevelHistory() async throws {
    let samples = (0..<1_024).map { Float($0 % 5) / 5 }
    let analysis = try XCTUnwrap(MicrophonePCMAnalyzer.analyze(channels: [samples]))
    XCTAssertEqual(analysis.waveform.count, MicrophonePCMAnalyzer.maximumWaveformBinCount)

    let authorization = MicrophoneAuthorizationFixture(state: .authorized)
    let capture = FixtureMicrophoneCaptureSession()
    let model = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: capture,
      minimumLevelHistoryInterval: 0
    )
    model.beginStart()
    for _ in 0..<(MicrophoneInputModel.maximumLevelHistoryCount + 50) {
      capture.emit(
        frameCount: 1_024,
        sampleRate: 48_000,
        channelCount: 2,
        analysis: analysis
      )
    }
    await waitUntil { model.observationCount == 350 }

    XCTAssertEqual(model.levelHistory.count, MicrophoneInputModel.maximumLevelHistoryCount)
    XCTAssertEqual(model.levelHistory.first?.id, 51)
    XCTAssertEqual(model.levelHistory.last?.id, 350)
  }

  func testMicrophoneSpectrumFindsExactSineBinWithBoundedOutput() throws {
    let sampleRate = 48_000.0
    let samples = (0..<1_024).map { frame in
      Float(0.5 * sin(2 * Double.pi * 3_000 * Double(frame) / sampleRate))
    }
    let analysis = try XCTUnwrap(
      MicrophonePCMAnalyzer.analyze(
        channels: [samples, samples],
        sampleRate: sampleRate,
        spectrumAnalyzer: MicrophoneSpectrumAnalyzer()
      )
    )
    let spectrum = try XCTUnwrap(analysis.spectrum)

    XCTAssertEqual(spectrum.fftSize, 1_024)
    XCTAssertEqual(spectrum.frequencyResolutionHz, 46.875, accuracy: 0.000_001)
    XCTAssertEqual(spectrum.nyquistFrequencyHz, 24_000, accuracy: 0.000_001)
    XCTAssertEqual(
      try XCTUnwrap(spectrum.strongestBinCenterFrequencyHz),
      3_000,
      accuracy: 0.000_001
    )
    XCTAssertEqual(spectrum.bins.count, MicrophoneSpectrumAnalyzer.maximumDisplayBinCount)
    XCTAssertEqual(
      try XCTUnwrap(spectrum.bins.map(\.relativeMagnitudeDB).max()),
      0,
      accuracy: 0.000_001
    )
  }

  func testMicrophoneSpectrumReportsStrongerCompositeComponent() throws {
    let sampleRate = 48_000.0
    let samples = (0..<2_048).map { frame in
      let time = Double(frame) / sampleRate
      return Float(
        0.2 * sin(2 * Double.pi * 750 * time)
          + 0.6 * sin(2 * Double.pi * 3_000 * time)
      )
    }
    let spectrum = try XCTUnwrap(
      MicrophoneSpectrumAnalyzer().analyze(samples: samples, sampleRate: sampleRate)
    )

    XCTAssertEqual(spectrum.fftSize, 2_048)
    XCTAssertEqual(
      try XCTUnwrap(spectrum.strongestBinCenterFrequencyHz),
      3_000,
      accuracy: spectrum.frequencyResolutionHz / 2
    )
  }

  func testMicrophoneSpectrumTreatsSilenceAndConstantInputAsNoNonDCPeak() throws {
    for samples in [
      Array(repeating: Float.zero, count: 1_024),
      Array(repeating: Float(0.25), count: 1_024),
    ] {
      let spectrum = try XCTUnwrap(
        MicrophoneSpectrumAnalyzer().analyze(samples: samples, sampleRate: 48_000)
      )
      XCTAssertNil(spectrum.strongestBinCenterFrequencyHz)
      XCTAssertTrue(
        spectrum.bins.allSatisfy {
          $0.relativeMagnitudeDB == MicrophoneSpectrumAnalyzer.displayFloorDB
        }
      )
    }
  }

  func testMicrophoneSpectrumRejectsInvalidInputAndCapsFFTSize() throws {
    let analyzer = MicrophoneSpectrumAnalyzer()
    XCTAssertNil(analyzer.analyze(samples: Array(repeating: 0, count: 255), sampleRate: 48_000))
    XCTAssertNil(analyzer.analyze(samples: Array(repeating: 0, count: 256), sampleRate: 0))
    XCTAssertNil(analyzer.analyze(samples: Array(repeating: 0, count: 256), sampleRate: .nan))
    XCTAssertNil(analyzer.analyze(samples: Array(repeating: .nan, count: 256), sampleRate: 48_000))
    XCTAssertNil(
      analyzer.analyze(
        samples: Array(repeating: 0, count: MicrophonePCMAnalyzer.maximumFrameCount + 1),
        sampleRate: 48_000
      )
    )

    let bounded = try XCTUnwrap(
      analyzer.analyze(samples: Array(repeating: 0, count: 4_096), sampleRate: 48_000)
    )
    XCTAssertEqual(bounded.fftSize, 2_048)
    XCTAssertEqual(bounded.bins.count, MicrophoneSpectrumAnalyzer.maximumDisplayBinCount)
  }

  func testMicrophoneSpectrumCadenceAndModelRetainOnlyLatestDerivedSpectrum() async throws {
    let cadence = MicrophoneSpectrumCadence()
    XCTAssertTrue(cadence.shouldAnalyze(frameCount: 1_024, sampleRate: 48_000))
    XCTAssertFalse(cadence.shouldAnalyze(frameCount: 1_024, sampleRate: 48_000))
    XCTAssertFalse(cadence.shouldAnalyze(frameCount: 1_024, sampleRate: 48_000))
    XCTAssertFalse(cadence.shouldAnalyze(frameCount: 1_024, sampleRate: 48_000))
    XCTAssertTrue(cadence.shouldAnalyze(frameCount: 1_024, sampleRate: 48_000))
    XCTAssertFalse(cadence.shouldAnalyze(frameCount: 0, sampleRate: 48_000))

    let samples = (0..<1_024).map { frame in
      Float(0.25 * sin(2 * Double.pi * Double(frame) / 64))
    }
    let spectrumAnalysis = try XCTUnwrap(
      MicrophonePCMAnalyzer.analyze(
        channels: [samples, samples],
        sampleRate: 48_000,
        spectrumAnalyzer: MicrophoneSpectrumAnalyzer()
      )
    )
    let baseAnalysis = try XCTUnwrap(
      MicrophonePCMAnalyzer.analyze(channels: [samples, samples])
    )
    let authorization = MicrophoneAuthorizationFixture(state: .authorized)
    let capture = FixtureMicrophoneCaptureSession()
    let model = MicrophoneInputModel(
      authorizationClient: authorization.client,
      captureSession: capture
    )
    model.beginStart()
    capture.emit(
      frameCount: 1_024,
      sampleRate: 48_000,
      channelCount: 2,
      analysis: spectrumAnalysis
    )
    await waitUntil { model.latestSpectrum != nil }
    let retainedSpectrum = try XCTUnwrap(model.latestSpectrum)

    capture.emit(
      frameCount: 1_024,
      sampleRate: 48_000,
      channelCount: 2,
      analysis: baseAnalysis
    )
    await waitUntil { model.observationCount == 2 }
    XCTAssertEqual(model.latestSpectrum, retainedSpectrum)

    model.leaveExperiment()
    XCTAssertNil(model.latestSpectrum)
  }

  func testMicrophoneInputSourceLimitsRawSampleAccessAndSystemMutation() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let inputSourceURL = projectRoot.appendingPathComponent(
      "Sources/MacSensorLab/MicrophoneInputView.swift"
    )
    let analysisSourceURL = projectRoot.appendingPathComponent(
      "Sources/MacSensorLab/MicrophoneAnalysis.swift"
    )
    let inputSource = try String(contentsOf: inputSourceURL, encoding: .utf8)
    let analysisSource = try String(contentsOf: analysisSourceURL, encoding: .utf8)
    let combinedSource = inputSource + analysisSource

    XCTAssertTrue(inputSource.contains("confirmPermissionAndStart"))
    XCTAssertEqual(
      inputSource.components(separatedBy: "AVCaptureDevice.requestAccess").count - 1,
      1
    )
    XCTAssertEqual(analysisSource.components(separatedBy: "floatChannelData").count - 1, 1)
    for forbidden in [
      "int16ChannelData", "int32ChannelData", "audioBufferList", "AVAudioRecorder",
      "AVAudioFile", "FileHandle", "tccutil", "NSWorkspace.open", "UserDefaults",
    ] {
      XCTAssertFalse(
        combinedSource.contains(forbidden),
        "Forbidden microphone path: \(forbidden)"
      )
    }
  }

  func testWiFiChannelScanModelPublishesACompletedFixtureAndCooldown() async throws {
    let result = wifiScanFixture()
    let model = WiFiChannelScanModel(
      timeout: .seconds(1),
      cooldown: .seconds(1),
      operation: { .success(result) }
    )

    model.start()
    await waitUntil { model.status != .scanning }

    XCTAssertEqual(model.status, .ready)
    XCTAssertEqual(model.result, result)
    XCTAssertFalse(model.isAwaitingResult)
    XCTAssertFalse(model.isOperationInFlight)
    XCTAssertTrue(model.isCoolingDown)
    XCTAssertFalse(model.canStart)
  }

  func testWiFiChannelScanModelTimesOutPresentationWithoutStartingAnotherScan() async {
    let result = wifiScanFixture()
    let model = WiFiChannelScanModel(
      timeout: .milliseconds(10),
      cooldown: .seconds(1),
      operation: {
        try? await Task.sleep(for: .milliseconds(60))
        return .success(result)
      }
    )

    model.start()
    await waitUntil { model.status == .timedOutWaiting }

    XCTAssertNil(model.result)
    XCTAssertFalse(model.isAwaitingResult)
    XCTAssertTrue(model.isOperationInFlight)
    XCTAssertFalse(model.canStart)

    await waitUntil { !model.isOperationInFlight }
    XCTAssertEqual(model.status, .timedOutWaiting)
    XCTAssertNil(model.result)
    XCTAssertTrue(model.isCoolingDown)
  }

  func testWiFiChannelScanModelStopWaitingDiscardsLateResultAndLeavingClearsSession() async {
    let result = wifiScanFixture()
    let model = WiFiChannelScanModel(
      timeout: .seconds(1),
      cooldown: .milliseconds(1),
      operation: {
        try? await Task.sleep(for: .milliseconds(30))
        return .success(result)
      }
    )

    model.start()
    model.stopWaiting()
    XCTAssertEqual(model.status, .stoppedWaiting)
    XCTAssertTrue(model.isOperationInFlight)
    XCTAssertNil(model.result)

    await waitUntil { !model.isOperationInFlight }
    XCTAssertEqual(model.status, .stoppedWaiting)
    XCTAssertNil(model.result)

    model.leaveExperiment()
    XCTAssertEqual(model.status, .idle)
    XCTAssertNil(model.result)
  }

  func testUSBInventoryModelPublishesOneCompletedFixture() async {
    let result = usbInventoryFixture()
    let operation = USBInventoryOperationFixture(
      delay: .milliseconds(10), outcome: .success(result))
    let model = USBInventoryModel(
      timeout: .seconds(1),
      operation: { await operation.read() }
    )

    model.start()
    model.start()
    await waitUntil { model.status == .ready }

    XCTAssertEqual(model.result, result)
    let completedReadCount = await operation.readCount
    XCTAssertEqual(completedReadCount, 1)
    XCTAssertFalse(model.isAwaitingResult)
    XCTAssertFalse(model.isOperationInFlight)
    XCTAssertTrue(model.canStart)
  }

  func testUSBInventoryModelTimesOutAndDiscardsTheLateResult() async {
    let result = usbInventoryFixture()
    let operation = USBInventoryOperationFixture(
      delay: .milliseconds(60), outcome: .success(result))
    let model = USBInventoryModel(
      timeout: .milliseconds(10),
      operation: { await operation.read() }
    )

    model.start()
    await waitUntil { model.status == .timedOutWaiting }
    XCTAssertNil(model.result)
    XCTAssertTrue(model.isOperationInFlight)
    XCTAssertFalse(model.canStart)

    await waitUntil { !model.isOperationInFlight }
    XCTAssertEqual(model.status, .timedOutWaiting)
    XCTAssertNil(model.result)
    let completedReadCount = await operation.readCount
    XCTAssertEqual(completedReadCount, 1)
  }

  func testUSBInventoryModelClearsOnLeaveAndIgnoresAnInFlightResult() async {
    let result = usbInventoryFixture()
    let operation = USBInventoryOperationFixture(
      delay: .milliseconds(40), outcome: .success(result))
    let model = USBInventoryModel(
      timeout: .seconds(1),
      operation: { await operation.read() }
    )

    model.start()
    model.leaveInventory()
    XCTAssertEqual(model.status, .idle)
    XCTAssertNil(model.result)
    XCTAssertTrue(model.isOperationInFlight)

    await waitUntil { !model.isOperationInFlight }
    XCTAssertEqual(model.status, .idle)
    XCTAssertNil(model.result)
  }

  func testCameraInventoryModelPublishesOneCompletedFixture() async {
    let result = cameraInventoryFixture()
    let operation = CameraInventoryOperationFixture(
      delay: .milliseconds(10), outcome: .success(result))
    let model = CameraInventoryModel(
      timeout: .seconds(1),
      operation: { await operation.read() }
    )

    model.start()
    model.start()
    await waitUntil { model.status == .ready }

    XCTAssertEqual(model.result, result)
    let completedReadCount = await operation.readCount
    XCTAssertEqual(completedReadCount, 1)
    XCTAssertFalse(model.isAwaitingResult)
    XCTAssertFalse(model.isOperationInFlight)
    XCTAssertTrue(model.canStart)
  }

  func testCameraInventoryModelTimesOutAndDiscardsTheLateResult() async {
    let result = cameraInventoryFixture()
    let operation = CameraInventoryOperationFixture(
      delay: .milliseconds(60), outcome: .success(result))
    let model = CameraInventoryModel(
      timeout: .milliseconds(10),
      operation: { await operation.read() }
    )

    model.start()
    await waitUntil { model.status == .timedOutWaiting }
    XCTAssertNil(model.result)
    XCTAssertTrue(model.isOperationInFlight)
    XCTAssertFalse(model.canStart)

    await waitUntil { !model.isOperationInFlight }
    XCTAssertEqual(model.status, .timedOutWaiting)
    XCTAssertNil(model.result)
    let completedReadCount = await operation.readCount
    XCTAssertEqual(completedReadCount, 1)
  }

  func testCameraInventoryModelClearsOnLeaveAndIgnoresAnInFlightResult() async {
    let result = cameraInventoryFixture()
    let operation = CameraInventoryOperationFixture(
      delay: .milliseconds(40), outcome: .success(result))
    let model = CameraInventoryModel(
      timeout: .seconds(1),
      operation: { await operation.read() }
    )

    model.start()
    model.leaveInventory()
    XCTAssertEqual(model.status, .idle)
    XCTAssertNil(model.result)
    XCTAssertTrue(model.isOperationInFlight)

    await waitUntil { !model.isOperationInFlight }
    XCTAssertEqual(model.status, .idle)
    XCTAssertNil(model.result)
  }

  func testCameraInventoryModelReplacesResultsAndKeepsEmptyAndFailureDistinct() async {
    let limited = cameraInventoryFixture(positionRawValue: 99)
    guard case .success(let empty) = CameraInventoryReducer.reduce(devices: []) else {
      return XCTFail("Expected an empty camera fixture")
    }
    let sequence = CameraInventoryOutcomeSequence(
      outcomes: [
        .success(limited),
        .success(empty),
        .failure(.discoveryUnavailable),
      ]
    )
    let model = CameraInventoryModel(
      timeout: .seconds(1),
      operation: { await sequence.read() }
    )

    model.start()
    await waitUntil { model.status == .limited }
    XCTAssertEqual(model.result, limited)

    model.start()
    await waitUntil { model.status == .empty }
    XCTAssertEqual(model.result, empty)

    model.start()
    await waitUntil { model.status == .failed(.discoveryUnavailable) }
    XCTAssertNil(model.result)
    let completedReadCount = await sequence.readCount
    XCTAssertEqual(completedReadCount, 3)
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @MainActor () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
      await Task.yield()
    }
  }

  private func wifiScanFixture() -> WiFiChannelScanResult {
    WiFiChannelScanResult(
      completedAt: Date(timeIntervalSince1970: 10),
      reportedRecordCount: 1,
      acceptedRecordCount: 1,
      discardedRecordCount: 0,
      truncatedRecordCount: 0,
      channels: [
        WiFiChannelScanSummary(
          band: .band5GHz,
          channelNumber: 44,
          reportedRecordCount: 1,
          strongestRSSIDBm: -50,
          averageRSSIDBm: -50,
          reportedChannelWidthsMHz: [80]
        )
      ]
    )
  }

  private func usbInventoryFixture() -> USBInventorySnapshot {
    guard
      case .success(let snapshot) = USBInventoryReducer.reduce(
        devices: [USBInventoryRawDevice(sourceIndex: 1, deviceClass: .integer(9))],
        interfaces: [],
        completedAt: Date(timeIntervalSince1970: 20)
      )
    else {
      preconditionFailure("Static USB fixture must reduce")
    }
    return snapshot
  }

  private func cameraInventoryFixture(positionRawValue: Int = 0) -> CameraInventorySnapshot {
    guard
      case .success(let snapshot) = CameraInventoryReducer.reduce(
        devices: [
          CameraInventoryRawDevice(
            sourceIndex: 1,
            deviceType: .builtInWideAngle,
            positionRawValue: positionRawValue,
            formats: [
              CameraInventoryRawFormat(
                sourceIndex: 0,
                width: 1_280,
                height: 720,
                frameRateRanges: [
                  CameraInventoryRawFrameRateRange(minimum: 30, maximum: 30)
                ],
                autofocusSystemRawValue: 0,
                colorSpaceRawValues: [0]
              )
            ]
          )
        ],
        completedAt: Date(timeIntervalSince1970: 30)
      )
    else {
      preconditionFailure("Static Camera Capabilities fixture must reduce")
    }
    return snapshot
  }
}

private actor USBInventoryOperationFixture {
  let delay: Duration
  let outcome: USBInventoryOutcome
  private var count = 0

  init(delay: Duration, outcome: USBInventoryOutcome) {
    self.delay = delay
    self.outcome = outcome
  }

  var readCount: Int { count }

  func read() async -> USBInventoryOutcome {
    count += 1
    try? await Task.sleep(for: delay)
    return outcome
  }
}

private actor CameraInventoryOperationFixture {
  let delay: Duration
  let outcome: CameraInventoryOutcome
  private var count = 0

  init(delay: Duration, outcome: CameraInventoryOutcome) {
    self.delay = delay
    self.outcome = outcome
  }

  var readCount: Int { count }

  func read() async -> CameraInventoryOutcome {
    count += 1
    try? await Task.sleep(for: delay)
    return outcome
  }
}

private actor CameraInventoryOutcomeSequence {
  private var outcomes: [CameraInventoryOutcome]
  private var count = 0

  init(outcomes: [CameraInventoryOutcome]) {
    self.outcomes = outcomes
  }

  var readCount: Int { count }

  func read() -> CameraInventoryOutcome {
    count += 1
    guard !outcomes.isEmpty else { return .failure(.failed) }
    return outcomes.removeFirst()
  }
}

@MainActor
private final class MicrophoneAuthorizationFixture {
  var state: MicrophoneAuthorizationState
  var requestResult: MicrophoneAuthorizationState
  var requestDelay: Duration = .zero
  private(set) var requestCount = 0

  init(state: MicrophoneAuthorizationState) {
    self.state = state
    self.requestResult = state
  }

  var client: MicrophoneAuthorizationClient {
    MicrophoneAuthorizationClient(
      current: { [weak self] in self?.state ?? .restricted },
      request: { [weak self] in
        guard let self else { return .restricted }
        self.requestCount += 1
        if self.requestDelay > .zero {
          try? await Task.sleep(for: self.requestDelay)
        }
        self.state = self.requestResult
        return self.state
      }
    )
  }
}

@MainActor
private final class FixtureMicrophoneCaptureSession: MicrophoneCaptureSession {
  var startError: MicrophoneCaptureSessionError?
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private var observationHandler: (@Sendable (MicrophonePCMObservation) -> Void)?
  private var lastObservationHandler: (@Sendable (MicrophonePCMObservation) -> Void)?
  private var terminationHandler: (@Sendable (MicrophoneCaptureTermination) -> Void)?

  func start(
    onObservation: @escaping @Sendable (MicrophonePCMObservation) -> Void,
    onTermination: @escaping @Sendable (MicrophoneCaptureTermination) -> Void
  ) throws -> MicrophonePCMFormatMetadata {
    startCount += 1
    if let startError { throw startError }
    observationHandler = onObservation
    lastObservationHandler = onObservation
    terminationHandler = onTermination
    return MicrophonePCMFormatMetadata(sampleRate: 48_000, channelCount: 2)!
  }

  func stop() {
    stopCount += 1
    observationHandler = nil
    terminationHandler = nil
  }

  func emit(
    frameCount: Int,
    sampleRate: Double,
    channelCount: Int,
    analysis: MicrophonePCMAnalysis = microphoneAnalysisFixture()
  ) {
    guard
      let observation = MicrophonePCMObservation(
        frameCount: frameCount,
        sampleRate: sampleRate,
        channelCount: channelCount,
        analysis: analysis
      )
    else { return }
    observationHandler?(observation)
  }

  func emitLate(
    frameCount: Int,
    sampleRate: Double,
    channelCount: Int,
    analysis: MicrophonePCMAnalysis = microphoneAnalysisFixture()
  ) {
    guard
      let observation = MicrophonePCMObservation(
        frameCount: frameCount,
        sampleRate: sampleRate,
        channelCount: channelCount,
        analysis: analysis
      )
    else { return }
    lastObservationHandler?(observation)
  }

  func terminate(_ reason: MicrophoneCaptureTermination) {
    terminationHandler?(reason)
  }
}

private func microphoneAnalysisFixture() -> MicrophonePCMAnalysis {
  MicrophonePCMAnalyzer.analyze(channels: [[0, 0.25, 0, -0.25]])!
}

@MainActor
private final class CameraAuthorizationFixture {
  var state: CameraAuthorizationState
  var requestResult: CameraAuthorizationState
  var requestDelay: Duration = .zero
  private(set) var requestCount = 0

  init(state: CameraAuthorizationState) {
    self.state = state
    self.requestResult = state
  }

  var client: CameraAuthorizationClient {
    CameraAuthorizationClient(
      current: { [weak self] in self?.state ?? .restricted },
      request: { [weak self] in
        guard let self else { return .restricted }
        self.requestCount += 1
        if self.requestDelay > .zero {
          try? await Task.sleep(for: self.requestDelay)
        }
        self.state = self.requestResult
        return self.state
      }
    )
  }
}

@MainActor
private final class FixtureCameraCaptureSession: CameraCaptureSession {
  var startError: CameraCaptureSessionError?
  var startsSuccessfully = true
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private var observationHandler: (@Sendable (CameraFrameObservation) -> Void)?
  private var lastObservationHandler: (@Sendable (CameraFrameObservation) -> Void)?
  private var terminationHandler: (@Sendable (CameraCaptureTermination) -> Void)?

  func start(
    onStarted: @escaping @Sendable (Bool) -> Void,
    onObservation: @escaping @Sendable (CameraFrameObservation) -> Void,
    onTermination: @escaping @Sendable (CameraCaptureTermination) -> Void
  ) throws -> CameraPreviewHandle? {
    startCount += 1
    if let startError { throw startError }
    observationHandler = onObservation
    lastObservationHandler = onObservation
    terminationHandler = onTermination
    onStarted(startsSuccessfully)
    return nil
  }

  func stop() {
    stopCount += 1
    observationHandler = nil
    terminationHandler = nil
  }

  func emit(_ observation: CameraFrameObservation) {
    observationHandler?(observation)
  }

  func emitLate(_ observation: CameraFrameObservation) {
    lastObservationHandler?(observation)
  }

  func terminate(_ reason: CameraCaptureTermination) {
    terminationHandler?(reason)
  }
}

private func cameraObservation(
  delivered: UInt64,
  dropped: UInt64 = 0,
  time: Double
) -> CameraFrameObservation {
  CameraFrameObservation(
    deliveredFrameCount: delivered,
    droppedFrameCount: dropped,
    observationUptimeSeconds: time,
    width: 1_280,
    height: 720,
    analysis: CameraFrameAnalysis(
      sampledPixelCount: 4_096,
      meanRelativeLuma: 0.45,
      minimumRelativeLuma: 0.1,
      maximumRelativeLuma: 0.8
    )
  )!
}

private actor SlowDashboardProvider: SensorProvider {
  nonisolated let metadata = SensorProviderMetadata(
    id: "test.slow",
    name: "Slow fixture",
    category: .diagnostics,
    source: "Test",
    capability: .publicAPI
  )

  func read() async -> SensorSnapshot {
    try? await Task.sleep(for: .milliseconds(200))
    return fixtureSnapshot(metadata: metadata)
  }
}

private struct FastDashboardProvider: SensorProvider {
  let metadata = SensorProviderMetadata(
    id: "test.fast",
    name: "Fast fixture",
    category: .diagnostics,
    source: "Test",
    capability: .publicAPI
  )

  func read() async -> SensorSnapshot { fixtureSnapshot(metadata: metadata) }
}

private func fixtureSnapshot(metadata: SensorProviderMetadata) -> SensorSnapshot {
  SensorSnapshot(
    id: metadata.id,
    name: metadata.name,
    category: metadata.category,
    summary: "Ready",
    status: .available,
    source: metadata.source,
    capability: metadata.capability,
    channels: [
      SensorChannel(id: "value", label: "Value", value: 1, formattedValue: "1")
    ]
  )
}
