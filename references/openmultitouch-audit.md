# OpenMultitouchSupport 4.0.0 静态准入审计

审计时间：2026-08-20。

结论：**当前版本不接入、不执行、不随 App 分发，也不解锁 Trackpad Scale。** 许可证与发布包完整性可以核验，但现成框架的设备标识日志、私有框架依赖、部署目标和发布签名边界不符合本项目当前要求。

## 固定输入

- 上游仓库：`Kyome22/OpenMultitouchSupport`
- 固定 commit：`15c6bb0c6a2d2858559493a28ab23f7ac58648a3`
- 许可证：MIT；仓库根许可证存在
- 上游 `Package.swift` 固定版本：[4.0.0 发布包](https://github.com/Kyome22/OpenMultitouchSupport/releases/download/4.0.0/OpenMultitouchSupportXCF.xcframework.zip)
- 上游声明的 SwiftPM checksum：`270d0b70d2dfa935f846b54d53004ec8bd6a0588996f56a0c06e5b39bab5afd4`
- 本地重新计算的 SHA-256 / SwiftPM checksum：与上游声明完全一致

下载包只保存在被 Git 忽略的 `.work/openmultitouch-audit/`，没有进入产品源码或发布资源。

## 静态核验结果

| 项目 | 结果 | 影响 |
|---|---|---|
| 归档完整性 | 重新计算的 checksum 与 `Package.swift` 完全一致 | 可以确认检查的是上游固定发布包，而不是来源不明的副本 |
| 架构 | 单一 macOS XCFramework slice，Mach-O 同时包含 `arm64` 与 `x86_64` | 架构覆盖本身不是阻塞项 |
| 动态链接 | 两个架构均直接链接 `/System/Library/PrivateFrameworks/MultitouchSupport.framework` | 属于私有接口；公开分发、系统更新兼容性和 notarization 必须独立评审 |
| 代码签名 | `codesign --verify --deep --strict` 通过；签名类型为 Apple Development | 只能证明当前归档内部签名一致，不能替代本项目的 Developer ID、Hardened Runtime 和 notarization |
| Hardened Runtime | CodeDirectory flags 为 `0x0`，没有 runtime flag | 不满足本项目未来公开二进制发布门槛 |
| Entitlements | 没有显示框架 entitlement | 不代表宿主 App 可以启用 App Sandbox |
| Sandbox | 上游 README 明确要求关闭 App Sandbox | 必须在产品安全边界中显式决策，不能静默接入 |
| 部署目标 | 上游 Swift Package 声明 macOS 15；本项目当前支持 macOS 14 | 直接添加 package dependency 会造成平台目标冲突 |
| 额外依赖 | Swift wrapper 还依赖 `swift-async-algorithms` | 接入时需要额外固定版本、许可证和供应链审计 |

本机 `spctl` 结果没有作为分发可信度证据：本地评估输出包含 security assessment override。项目没有尝试修改该系统状态。

## 阻塞性隐私问题

上游 `OpenMTManager.m` 的启动路径不仅创建默认触控板，还调用并写入系统日志：

- `MTDeviceGetGUID` / `GUID: ...`；
- `MTDeviceGetDeviceID` / `DeviceID: ...`；
- Driver Type、Family ID、传感面尺寸与网格尺寸。

发布二进制的字符串和未定义符号表同样包含 `GUID:`、`DeviceID:`、`MTDeviceGetGUID` 与 `MTDeviceGetDeviceID`，因此这不是只存在于未打包源码中的死文档。框架事件对象还保存 `deviceID`。这些行为违反 Mac Sensor Lab 不采集、不记录、不导出设备标识的隐私不变量；即使 Swift wrapper 当前不展示这些字段，也不能直接复用该二进制。

此外，上游 manager 注册系统睡眠/唤醒通知，并在唤醒时调用启动路径。未来实现必须只在用户明确开启实验且此前确实处于监听状态时恢复，不能因框架单例存在而自动启动触控数据流。

## 未来接入前必须满足

1. 只基于可审查的 MIT 源码制作最小 adapter；删除 GUID、DeviceID、Family ID 等读取、日志和事件字段，不复用当前预编译二进制。
2. 原始触点监听必须由用户在独立实验页明确启动，默认关闭；离开实验、关闭窗口、睡眠或任务取消时可靠停止。
3. 只保留实现压力/面积实验所需的最小短期内存数据；不自动记录，不把逐触点 ID、位置或时间流加入诊断导出。
4. 所有 Float 输入先验证有限值和合理范围，再进入校准、图表或导出；状态数组、采样频率和历史长度必须有硬上限。
5. 单独评审 macOS 14/15 支持、App Sandbox、Hardened Runtime、Developer ID 和 notarization；不能因为本地可运行就宣称可公开分发。
6. 固定所有源码与依赖 commit/checksum，补齐许可证，并在无触控板、权限/接口不可用、睡眠唤醒和多次开始/停止路径上加入测试。

在这些条件完成且经过新的隐私/发布评审前，现有 `diagnostics.hardware_capabilities` 只能报告 Force Touch 硬件存在性，不能被视为可用测量 Provider。
