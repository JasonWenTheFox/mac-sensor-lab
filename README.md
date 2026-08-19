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
3. 无需提权即可读取的系统、CPU/GPU 利用率、负载、内存/GPU 内存、交换空间、聚合网络吞吐量、磁盘 I/O、热状态、电池、电源、存储、显示和硬件存在性信息；
4. Apple SPU、AppleSMC、Force Touch 等实验性硬件的普通权限探测；
5. 无驱动写入的 SPU 实时报告尝试、环境光原始强度与四个光谱通道；
6. AppleSMC 的固定白名单温度、风扇转速与功耗只读通道；
7. 上盖角度 feature report 和派生量角器数据源；
8. 原始值/解释值区分、JSON/CSV 快照导出、受大小保护的连续 CSV 记录和 CLI 自检；
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

本机可使用完整 Xcode；如果 Xcode 首次组件仍在安装，也可显式使用 Command Line Tools：

```bash
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift run sensorlab-selftest
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift run sensorlab-selftest --spu-stability
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift run sensorlab-selftest --portable
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift run sensorlab-probe
./scripts/build-app.sh
./scripts/release-audit.sh
open "outputs/Mac Sensor Lab.app"
```

Command Line Tools 不包含本项目测试所需的 XCTest 模块。首次安装 Xcode 时，许可和组件初始化必须由用户本人完成；项目本身不会调用 `sudo`：

```bash
sudo xcodebuild -license
sudo xcodebuild -runFirstLaunch
xcodebuild -checkFirstLaunchStatus
swift test
```

`scripts/build-app.sh` 会在 Xcode 尚不可用时自动回退到 Command Line Tools，生成并临时签名本地 `.app`，不会修改全局开发者目录。

`scripts/release-audit.sh` 只检查本仓库的已跟踪文件和发布资源：阻止构建产物、绝对用户路径、密钥特征、未实现的受保护权限、危险写入 API 或与当前离线行为不一致的 Privacy Manifest 进入发布分支。

## 采样与记录

- 工具栏可选择 1、2、5 或 10 秒自动刷新，也可以暂停/恢复；暂停后手动刷新仍然可用。
- 采样间隔保存在本 App 自己的偏好中；暂停状态不会跨启动恢复。Settings 和工具栏使用同一设置。
- 图表最多保留 600 个不同时间戳的内存样本，`Clear Chart History` 不会删除任何文件。
- `Export` 菜单可以导出当前 JSON/CSV 快照，或由用户主动选择文件后开始连续 CSV 记录。
- 连续 CSV 分开保存机器可读的 `raw_value` 和界面使用的 `formatted_value`；每批写入后同步，Recorder 内部按 Provider 时间戳/状态去重，默认达到 50 MB 前自动停止。
- Light Meter 显示原始值的滚动最小/平均/最大；只有用户输入外部照度参考并主动校准后，才增加明确标为 `Estimated` 的 `ambient_estimated_lux` 通道。
- 单点光照校准可以由用户主动导入/导出为 JSON；文件只保存原始参考值、外部 lux 参考值和校准时间，导入时会重新验证有限正数，不读取或写入设备标识。
- Lid Protractor 可以把当前开合角设为参考，并显示带方向的相对角度变化；不会改变或重新配置传感器。
- App 不会自动开始记录，不会上传数据，也不会把用户选择的记录文件加入仓库。
- Dashboard 使用单一原生窗口，避免多个窗口为同一硬件启动互相争用的采样循环；关闭窗口时会安全结束仍在进行的连续记录。
- Raw Sensors 支持按 Provider、通道、来源、状态或稳定 ID 做本地即时搜索；通道命中时只收窄显示，不改变底层采样或导出内容。
- Raw Sensors 的每个 Provider 页脚显示该 Snapshot 的实际时间戳；最近样本降级不会伪装成新的更新时间。
- Diagnostics 可由用户主动导出隐私安全的支持报告；它只含 Provider 状态和稳定通道元数据，不含传感器读数、自由文本、机器标识或文件路径。

## 当前可读能力

| 数据源 | 当前状态 | 安全边界 |
|---|---|---|
| 系统性能 | 可用 | Mach 汇总 CPU tick、内存页分类、负载和 swap；不读取进程列表或机器唯一标识 |
| GPU 性能 | Apple Silicon 条件可用 | AGX 固定统计键白名单；利用率与 GPU 内存，不读取 registry 名称、ID 或设备身份字段 |
| 网络吞吐量 | 可用 | BSD 聚合计数器；只汇总启用的非回环接口，不导出接口名、地址、SSID、BSSID 或 MAC 地址 |
| 磁盘活动 | 可用 | IOKit 固定统计字段；聚合读写字节、操作数和错误数，不读取设备名、序列号、卷名或文件路径 |
| 系统、显示、存储、热压力 | 可用 | 公开 API；不导出机器唯一标识 |
| 电池 | 可用 | 固定非识别字段白名单；含充电、电气、温度、设计/报告容量和有效时的时间估算 |
| SMC 温度、风扇、功耗 | 可用 | 固定 key 白名单；没有写入或风扇控制方法 |
| 上盖角度 | 可用 | 一次性只读 feature report |
| 环境光 | 可用时实时读取 | 原始强度与光谱通道；可选单点外部参考生成 Estimated lux；短暂争用时保留原时间戳的最近样本 |
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
- [x] 建立私有 GitHub 仓库并通过首轮 CI。
- [x] 用户接受 Xcode 许可。
- [x] 完成 Xcode 首次组件初始化并在本机通过 23 项 XCTest。
- [x] 加入可调采样、暂停/恢复、历史清空和 50 MB 上限的连续 CSV 记录。
- [x] 加入环境光滚动统计、可选 Estimated lux 和上盖相对角度实验。
- [x] 加入严格校验且不含设备标识的单点光照校准 JSON 导入/导出。
- [x] 加入汇总 CPU 利用率、1/5/15 分钟负载、Mach 内存分类和 swap Provider。
- [x] 加入不导出网络标识的聚合上下行吞吐量、包速率和累计字节 Provider。
- [x] 加入不读取磁盘身份信息的聚合读写吞吐量、操作速率和驱动错误计数 Provider。
- [x] 随 App Bundle 打包并校验 Privacy Manifest，明确声明不跟踪、不联网收集数据。
- [x] 为 Raw Sensors 加入不影响原始数据的 Provider/通道/来源/ID 搜索。
- [x] 扩展电池固定白名单，加入设计容量、报告容量、派生容量比例和有效时间估算。
- [x] 加入只读取 AGX 固定统计键的 GPU/Renderer/Tiler 利用率和 GPU 内存 Provider。
- [x] 加入不含传感器读数和自由文本的隐私安全诊断 JSON 导出。
- [x] 在 CI 中加入项目范围的发布边界与隐私清单审计。
- [ ] 用户确认正式名称后公开 GitHub 仓库。

## 重要边界

本项目不是医疗、计量、工业安全或法定测量仪器。未经外部基准校准的读数只能用于观察、比较、教育和实验。

开发与发布细节见 [`docs/05-当前实现与后续路线.md`](docs/05-当前实现与后续路线.md)、[`CONTRIBUTING.md`](CONTRIBUTING.md) 和 [`SECURITY.md`](SECURITY.md)。
