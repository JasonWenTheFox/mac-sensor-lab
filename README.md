# Mac Sensor Lab

简体中文 | [English](README.en.md)

> 工作名。一个事实优先、原生、可扩展的 macOS 传感器查看与实验工具。

状态：active
优先级：high
主要产出：software
创建时间：2026-08-03
最近更新：2026-08-20
代码仓库：GitHub（当前私有，公开发布前加固中）
许可证：MIT；第三方代码继续遵守各自许可证
数据位置：项目内仅保存脱敏测试夹具；大型或私密采样不进入仓库

## 界面预览

![Mac Sensor Lab 使用确定性 Demo Provider 的 Overview](docs/images/overview-demo.png)

截图使用明确标识的内置 Demo fixture，不包含这台 Mac 的真实传感器读数或机器标识。

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
6. AppleSMC 的 M1–M5 分代固定白名单温度、风扇转速与功耗只读通道；
7. 上盖角度 feature report 和派生量角器数据源；
8. 原始值/解释值区分、JSON/CSV 快照导出、受大小保护的连续 CSV 记录、Provider 数据契约审计和 CLI 自检；
9. 英文/简体中文原生界面本地化，并保持导出中的稳定 ID 和原始数据不变；
10. 对缺失、权限不足、超时和未校准提供清楚的降级状态。

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
├── Resources/        App 元数据、图标、隐私清单和本地化资源
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
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift run sensorlab-probe -- --demo
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift run sensorlab-probe -- --diagnostics
./scripts/build-app.sh
./scripts/build-app.sh release
./scripts/release-audit.sh
open "outputs/Mac Sensor Lab.app"
open "outputs/Mac Sensor Lab.app" --args --demo
```

Command Line Tools 不包含本项目测试所需的 XCTest 模块。首次安装 Xcode 时，许可和组件初始化必须由用户本人完成；项目本身不会调用 `sudo`：

```bash
sudo xcodebuild -license
sudo xcodebuild -runFirstLaunch
xcodebuild -checkFirstLaunchStatus
swift test
```

`scripts/build-app.sh` 会在 Xcode 尚不可用时自动回退到 Command Line Tools，生成并临时签名本地 Debug `.app`；传入 `release` 会从优化后的 Release 可执行文件组装 App。打包时会校验 String Catalog 与生成的简体中文 `.lproj` 一致，并拒绝在 Release 可执行文件中留下开发机的绝对用户目录构建路径。两种模式都不会修改全局开发者目录，CI 使用 Release 模式复验。

`scripts/release-audit.sh` 只检查本仓库的已跟踪文件和发布资源：阻止构建产物、绝对用户路径、密钥特征、未实现的受保护权限、危险写入 API、失配的本地化产物或与当前离线行为不一致的 Privacy Manifest 进入发布分支。

原生 UI 当前支持英文和简体中文，跟随 macOS 的 App 语言设置。Provider 名称、动态摘要、通道标签、枚举值、单位和项目自有说明均在白名单展示层中本地化；Provider/Channel 稳定 ID、JSON/CSV 字段与原始传感器数据不会随语言变化。

显式 `--demo` 启动参数使用 14 个内置、确定性且无机器标识的 Provider fixture。全界面会显示 Demo 横幅，并使用独立的采样、光照校准和上盖参考偏好键，适合截图、UI 回归和无对应硬件的演示；它绝不会伪装成实时读数。

`sensorlab-probe` 同样支持 `--demo`；加上 `--diagnostics` 时只输出无传感器读数/自由文本的隐私安全 Provider 元数据，并在非法、重复或识别性 ID 出现时拒绝导出。无参数时仍按原行为读取真实 Provider 并在本地标准输出完整快照。

`sensorlab-selftest` 会对注册信息和实际 Snapshot 执行结构化数据契约审计：检查 Provider/通道稳定 ID、唯一性、注册元数据一致性、有限数值、非空且有界的显示字段、Provider/通道/备注数量上限、状态与通道一致性、未来时间戳，以及禁止进入 ID 的机器识别字段名。审计不会把摘要、备注等自由文本与隐私关键词匹配，也不会采集额外数据。

Dashboard 还会在每个 Provider 结果进入 UI、历史或记录前执行同一结构契约与注册元数据核对；畸形结果会在固定注册位置变成不回显原负载的 Error Snapshot，不能通过变化 ID 让状态数组持续增长。

## 采样与记录

- 工具栏可选择 1、2、5 或 10 秒自动刷新，也可以暂停/恢复；暂停后手动刷新仍然可用。
- 采样间隔保存在本 App 自己的偏好中；暂停状态不会跨启动恢复。Settings 和工具栏使用同一设置。
- 图表只缓存当前绘图/派生功能需要的通道，总计最多 256 条序列、每条 600 个严格递增时间戳的内存样本；`Clear Chart History` 不会删除任何文件。
- `Export` 菜单可以导出当前 JSON/CSV 快照，或由用户主动选择文件后开始连续 CSV 记录。
- App 创建的快照、诊断、校准和记录文件先在目标目录以 `0600`（仅当前用户读写）建立临时文件，同步后原子替换目标；不会改变目标目录或系统权限策略。
- 连续 CSV 分开保存机器可读的 `raw_value` 和界面使用的 `formatted_value`；文本列防止表格软件公式解释，每批先验证完整 Snapshot 契约、逐行计算 UTF-8 大小并确认整批可容纳，再以单行峰值内存逐行写入并同步；Recorder 每批及停止时重新确认真实文件末尾和大小、按 Provider 时间戳/状态去重，跨批次最多跟踪 256 个 Provider，默认达到 50 MB 前自动停止。
- Light Meter 显示原始值的滚动最小/平均/最大；只有用户输入外部照度参考并主动校准后，才增加明确标为 `Estimated` 的 `ambient_estimated_lux` 通道。首点使用零偏移比例，2–8 个严格单调参考点使用归一化线性拟合并显示 RMSE，可撤销最后一点。
- 光照校准可以由用户主动导入/导出为 JSON；文件最多保存 8 组原始参考值、外部 lux 参考值和校准时间，导入时会重新验证有限正数、严格单调关系与数量上限，并限制为 64 KiB 本地文件。旧版单点 JSON 仍可导入，不读取或写入设备标识。
- Lid Protractor 可以把当前开合角设为参考，并显示带方向的相对角度变化；不会改变或重新配置传感器。
- Motion Trend 对低速加速度模长历史计算 RMS 变化量和峰峰值，并明确说明 1–10 秒 Dashboard 采样不能测量振动频率。
- App 不会自动开始记录，不会上传数据，也不会把用户选择的记录文件加入仓库。
- Dashboard 使用单一原生窗口，避免多个窗口为同一硬件启动互相争用的采样循环；关闭窗口时会安全结束仍在进行的连续记录。
- Overview 卡片显示 Snapshot 原始时间戳的动态相对时间；SPU 短暂缺报时保留的降级样本不会看起来像刚刚采集的新值。
- Raw Sensors 支持按 Provider、通道、来源、状态或稳定 ID 做本地即时搜索，也可匹配当前界面语言中的已本地化名称；通道命中时只收窄显示，不改变底层采样或导出内容。
- Raw Sensors 的每个 Provider 页脚显示该 Snapshot 的实际时间戳；最近样本降级不会伪装成新的更新时间。
- Diagnostics 分开显示加载中、受限、权限不足、不可用和错误，避免把权限拒绝笼统算作“不可用”；同时显示本次启动内的刷新次数、最近耗时和 Provider 状态切换计数。用户主动导出的隐私安全支持报告可包含这些纯计数及稳定通道元数据，但不含传感器读数、自由文本、机器标识、Snapshot 时间戳或文件路径。

## 当前可读能力

| 数据源 | 当前状态 | 安全边界 |
|---|---|---|
| 系统性能 | 可用 | Mach 汇总 CPU tick、内存页分类、负载和 swap；不读取进程列表或机器唯一标识 |
| GPU 性能 | Apple Silicon 条件可用 | AGX 固定统计键白名单；利用率与 GPU 内存，不读取 registry 名称、ID 或设备身份字段 |
| 网络吞吐量 | 可用 | BSD 聚合计数器；只汇总启用的非回环接口，不导出接口名、地址、SSID、BSSID 或 MAC 地址 |
| 磁盘活动 | 可用 | IOKit 固定统计字段；聚合读写字节、操作数和错误数，不读取设备名、序列号、卷名或文件路径 |
| 系统、显示、存储、热压力 | 可用 | 公开 API；不导出机器唯一标识 |
| 电池 | 可用 | 固定非识别字段白名单；含充电、电气、温度、设计/报告容量和有效时的时间估算 |
| SMC 温度、风扇、功耗 | 可用 | M1–M5 分代与通用固定 key 白名单；只用非唯一 CPU 代际选表且不保留/导出品牌字符串；没有写入或风扇控制方法 |
| 上盖角度 | 可用 | 一次性只读 feature report |
| 环境光 | 可用时实时读取 | 原始强度与光谱通道；可选 1–8 点外部参考生成带 RMSE 的 Estimated lux；短暂争用时保留原时间戳的最近样本 |
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
- [x] 完成 Xcode 首次组件初始化并在本机通过 62 项 XCTest。
- [x] 加入可调采样、暂停/恢复、历史清空和 50 MB 上限的连续 CSV 记录。
- [x] 加入环境光滚动统计、可选 Estimated lux 和上盖相对角度实验。
- [x] 加入严格校验且不含设备标识的 1–8 点光照拟合、RMSE、撤销，以及兼容旧单点格式的 JSON 导入/导出。
- [x] 加入汇总 CPU 利用率、1/5/15 分钟负载、Mach 内存分类和 swap Provider。
- [x] 加入不导出网络标识的聚合上下行吞吐量、包速率和累计字节 Provider。
- [x] 加入不读取磁盘身份信息的聚合读写吞吐量、操作速率和驱动错误计数 Provider。
- [x] 随 App Bundle 打包并校验 Privacy Manifest，明确声明不跟踪、不联网收集数据。
- [x] 为 Raw Sensors 加入不影响原始数据的 Provider/通道/来源/ID 搜索。
- [x] 扩展电池固定白名单，加入设计容量、报告容量、派生容量比例和有效时间估算。
- [x] 加入只读取 AGX 固定统计键的 GPU/Renderer/Tiler 利用率和 GPU 内存 Provider。
- [x] 加入不含传感器读数和自由文本的隐私安全诊断 JSON 导出。
- [x] 在 CI 中加入项目范围的发布边界与隐私清单审计。
- [x] 加入明确标识且与真实偏好隔离的确定性 Demo Provider 模式。
- [x] 加入可复用且对超长文本执行前缀有界检查的 Provider/Snapshot 数据契约审计，并接入本地及 CI portable 自检。
- [x] Provider 排序对重复 ID 安全降级，不会在契约审计报告问题前触发运行时崩溃。
- [x] Demo 模式隔离采样、光照校准和上盖角度参考偏好，不污染 live 状态。
- [x] 加入隐私安全兼容性 Issue 表单、匿名贡献指南，并由发布审计强制检查。
- [x] 加入不保留读数和时间戳、最多跟踪 256 个 Provider 的采样健康统计，用于识别间歇性 Provider 状态抖动。
- [x] 对极端 CPU/网络/磁盘/GPU/内存/SMC 数值使用检查式算术，损坏计数不会触发整数转换或溢出崩溃。
- [x] 将 SMC 温度白名单按 M1–M5 代际分层，并用不含真实读数的各代 fixture 验证选表、通用键与未知代际降级。
- [x] 完成 OpenMultitouchSupport 4.0.0 静态准入审计；因现成二进制读取/日志输出设备标识、依赖私有框架、要求关闭 Sandbox 且发布边界未完成，当前明确不接入。
- [x] 建立英文/简体中文 String Catalog、中央本地化入口、键覆盖测试和 App Bundle `.lproj` 校验。
- [ ] 用户确认正式名称后公开 GitHub 仓库。

## 重要边界

本项目不是医疗、计量、工业安全或法定测量仪器。未经外部基准校准的读数只能用于观察、比较、教育和实验。

开发与发布细节见 [`docs/05-当前实现与后续路线.md`](docs/05-当前实现与后续路线.md)、[`docs/06-匿名兼容性贡献指南.md`](docs/06-匿名兼容性贡献指南.md)、[`references/openmultitouch-audit.md`](references/openmultitouch-audit.md)、[`CONTRIBUTING.md`](CONTRIBUTING.md) 和 [`SECURITY.md`](SECURITY.md)。
