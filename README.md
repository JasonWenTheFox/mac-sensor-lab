# Mac Sensor Lab

> 工作名。一个事实优先、原生、可扩展的 macOS 传感器查看与实验工具。

状态：active
优先级：high
主要产出：software
创建时间：2026-08-03
最近更新：2026-08-20
代码仓库：本地 Git 仓库（`main`）
许可证：MIT；第三方代码继续遵守各自许可证
数据位置：项目内仅保存脱敏测试夹具；大型或私密采样不进入仓库

## 项目目标

Mac Sensor Lab 希望填补 macOS 上“原始传感器浏览器 + 面向用户的测量工具”之间的空白：

- 尽可能完整地展示 Mac 实际可读取的传感器和系统遥测；
- 同时保留原始通道、单位、来源、采样率、权限与可信度；
- 在明确标注校准和不确定性的前提下提供水平仪、量角器、称重、振动、光照和声学等派生工具；
- 使用 Swift 和原生 macOS UI，界面快速出现，慢速传感器异步加载；
- 形成可以公开审查、复现和贡献的开源项目。

## 当前首版范围

首版优先建立可信的架构和可运行 App：

1. 原生 SwiftUI 总览和分组详情；
2. 统一的 Sensor Provider、状态、通道和历史样本模型；
3. 无需提权即可读取的系统、热状态、电池、电源、存储、显示和硬件存在性信息；
4. Apple SPU、AppleSMC、Force Touch 等实验性硬件的普通权限探测；
5. 无驱动写入的 SPU 实时报告尝试、环境光原始强度与四个光谱通道；
6. AppleSMC 的固定白名单温度、风扇转速与功耗只读通道；
7. 上盖角度 feature report 和派生量角器数据源；
8. 原始值/解释值区分、JSON/CSV 快照导出和 CLI 自检；
9. 对缺失、权限不足、超时和未校准提供清楚的降级状态。

加速度计/陀螺仪仅在 macOS 已经发布 HID 报告时读取；首版不会写入 Apple SPU 驱动属性来强制唤醒。触摸板原始压力与麦克风会按独立 Provider 逐步接入。当前阶段不安装特权 Helper，不让 App 以 root 运行。

## 目录

```text
.
├── README.md
├── AGENTS.md
├── Package.swift
├── Sources/
│   ├── SensorCore/
│   ├── MacSensorLab/
│   ├── SensorLabProbe/
│   └── SensorLabSelfTest/
├── Tests/
├── docs/
├── references/
├── LICENSES/
├── scripts/
├── outputs/          本地交付构建，不提交 Git
└── .work/            上游浅克隆、临时分析和构建中间文件
```

## 本地构建

本机目前已安装 Xcode，但首次许可尚未由用户接受。在此之前，可显式使用 Command Line Tools：

```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swift build
swift run sensorlab-selftest
swift run sensorlab-selftest --portable  # CI/无传感器机器
swift run sensorlab-probe
./scripts/build-app.sh
open "outputs/Mac Sensor Lab.app"
```

Command Line Tools 不包含本项目测试所需的 XCTest 模块，因此 `swift test` 要等完整 Xcode 首次许可完成后执行。许可必须由用户本人阅读和接受：

```bash
sudo xcodebuild -license
swift test
```

`scripts/build-app.sh` 会在 Xcode 尚不可用时自动回退到 Command Line Tools，生成并临时签名本地 `.app`，不会修改全局开发者目录。

## 当前可读能力

| 数据源 | 当前状态 | 安全边界 |
|---|---|---|
| 系统、显示、存储、热压力 | 可用 | 公开 API；不导出机器唯一标识 |
| 电池 | 可用 | 固定非识别字段白名单 |
| SMC 温度、风扇、功耗 | 可用 | 固定 key 白名单；没有写入或风扇控制方法 |
| 上盖角度 | 可用 | 一次性只读 feature report |
| 环境光 | 可用时实时读取 | 原始强度与光谱通道，不冒充校准 lux |
| 加速度计、陀螺仪 | 条件可用 | 只监听系统已发布报告，不写驱动唤醒状态 |
| Force Touch | 仅检测存在性 | 未加载私有二进制框架 |
| 麦克风 | 未启用 | 不主动触发录音权限 |

## 状态与下一步

- [x] 确认项目归入 `~/Projects/Software`。
- [x] 读取并提炼网页端需求。
- [x] 初步核验本机 Apple SPU HID、Force Touch 和 AppleSMC 的存在性。
- [x] 固定首批上游仓库和许可证边界。
- [x] 完成可构建的 SwiftUI 首版和 CLI 自检。
- [x] 完成真实数据、失败路径和 JSON/CSV 导出验证。
- [x] 添加 MIT 项目许可证和完整第三方许可证/归属信息。
- [x] 添加原创 App 图标和本地 `.icns` 打包资源。
- [x] 添加 macOS 26 / Xcode 26 CI 和 Pull Request 安全检查模板。
- [ ] 用户确认正式名称后建立公开 GitHub 仓库。
- [ ] 用户接受 Xcode 许可后运行 XCTest 和正式 Xcode 签名构建。

## 重要边界

本项目不是医疗、计量、工业安全或法定测量仪器。未经外部基准校准的读数只能用于观察、比较、教育和实验。

开发与发布细节见 [`docs/05-当前实现与后续路线.md`](docs/05-当前实现与后续路线.md)、[`CONTRIBUTING.md`](CONTRIBUTING.md) 和 [`SECURITY.md`](SECURITY.md)。
