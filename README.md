# Mac Sensor Lab

简体中文 | [English](README.en.md)

一个事实优先、离线工作的原生 macOS 传感器查看与实验工具。

> **0.3.1 显示与存储硬件基础源码预览版**：仓库可以公开审查、克隆和本地构建，但目前没有面向普通用户的已公证下载包。`outputs/Mac Sensor Lab.app` 使用 ad-hoc 签名，仅供本机开发验证；正式二进制仍需 Developer ID 签名、公证和更多机型测试。

![使用确定性 Demo Provider 的 Mac Sensor Lab Overview](docs/images/overview-demo.png)

截图来自明确标识的 `--demo` fixture，不包含开发机的真实读数或机器标识。

## 它能做什么

Mac Sensor Lab 把能力分成三层，并在界面和导出中保留数据来源：

1. **原始事实**：26 个独立 Provider，包括非唯一机型类别、SoC、CPU 拓扑、统一内存、Metal GPU 与 Touch ID 能力，公开 Core Audio 音频设备清单，每显示器模式/色域/EDR/估算尺寸，系统盘介质属性与 NVMe SMART 标量/无损累计计数，当前 Wi-Fi 无线电链路，以及系统性能、网络/磁盘汇总、电池/电源、热压力、只读 SMC、SPU 环境光/运动和上盖角度。
2. **可理解展示**：独立硬件清单页，卡片可按需展开全部事实，并提供用户主动、仅限当前页面的 USB 设备树与本机相机能力；同时展示状态、单位、来源、硬件领域、访问级别、兼容性证据、五段就绪状态、Raw/Derived/Estimated/Calibrated 类型、历史曲线、搜索和版本化 JSON/CSV 导出。
3. **实验解释**：会话内显示器物理尺、Force Touch 归一化压力/stage 可视化、Wi-Fi 信号/噪声趋势、用户主动的附近 Wi-Fi 信道快照、声音输入检查和相机检查、水平/运动趋势、上盖量角器、光照校准、四通道环境光谱相对指纹、电池趋势、热压力、部件温度、系统功耗、网络和磁盘活动。

环境光谱指纹只比较四个未知响应通道的相对比例，可保存当前光型作为本地参考并显示相似度；它不会冒充色温、光谱波长或 lux。环境照度只有在用户提供外部 lux 参考并校准后才标为 `Estimated`。内部温度不是室温，内部功耗不是插座功率，1–10 秒采样也不宣称能分析振动频率。

显示器物理尺寸在系统无法取得 EDID 时可能是 CoreGraphics 的 72 DPI 推算，因此系统尺寸、对角线和 PPI 始终标为 `Estimated`。实验页的物理尺允许用户用真实尺具校准当前显示器的水平轴，并把 `System Estimated` 与 `User Calibrated` 结果并列；它不推断垂直尺寸或对角线，结果只在当前 App 会话和显示模式中有效，也不进入 Snapshot 或导出。存储硬件仅汇总系统卷关联整盘的固定类别和数值，不从 Disk Arbitration 猜测 SMART。独立的 NVMe SMART Provider 只调用 Apple 公开 `SMARTReadData`，展示警告位、综合温度、备用空间、寿命消耗估算和 10 组 128-bit 累计计数。这些计数用无损十进制文本表示，不转为 `Double`；Data Units 的字节通道是报告单位的精确换算，由于原始单位向上取整，不代表精确历史 I/O 字节数。Provider 不读取设备型号、序列号、UUID、卷名、路径、identify 数据或详细错误日志，也不把字段合成单一“健康分”。

Force Touch Pressure Lab 由用户主动开始，只在 App 自己的交互区通过公开 AppKit 事件读取 `pressure`、`stage` 和 `stageTransition`。曲线在每次 stage 变化处分段，只保留最多 240 个内存样本，并在停止或离页后按界面说明清除；它不安装输入监控、不读取原始触点或设备 ID，也不进入 Snapshot 或导出。0…1 的 pressure 只表示每个 stage 内的归一化输入，不能解释为力、重量、克数或经过校准的物理测量。

Wi-Fi Radio Provider 使用公开 CoreWLAN getter 展示开关/服务/关联状态、RSSI、噪声、派生 SNR、频道、带宽、频段、PHY、安全模式、协商发送速率和发送功率；有错误哨兵或未知枚举时省略该字段。独立的 Nearby Wi-Fi Channels 实验只有在用户二次确认后才运行一次公开 CoreWLAN 扫描，并立即归约为频段、信道、报告记录数、RSSI 和带宽摘要；它不读取网络名、接入点地址、MAC/IP、接口名、国家代码、信息元素或位置，不请求定位权限，也不进入自动采样、Snapshot、Diagnostics 或导出。协商 PHY 速率不是应用实际吞吐量，扫描摘要也不等于空口占用或完整拥塞测量。

Audio Hardware Provider 只查询公开 Core Audio HAL 属性，展示当前可见/可用、输入/输出/双工设备数量，以及默认输入/输出的连接类别、通道数、标称采样率和设备级延迟。AudioDevice 数字句柄只在单次读取内临时使用；设备 UID、model UID、名称、厂商和驱动自由文本均不读取。它不会打开音频流、采集 PCM、录音或请求麦克风权限；标称采样率不是录音数据，设备延迟也不包含额外的 stream latency 与 safety offset。

USB Device Tree 与 Provider 和导出隔离，只有用户在 Hardware Inventory 点击后才通过公开 IOKit 读取一次当前树。它只保留有界 VID/PID、`bcdDevice`、设备/接口类别三元组、当前配置、连接速度类别、备用设置和当次父子关系；最多处理 128 个设备、512 个接口和 32 层父链。页面只显示本次快照序号，离页即清空；不读取 serial/container/location/path/name/descriptor/power，不打开 USB user client，不发请求、传输、配置或重置设备。连接速度不是设备最大能力或实测吞吐量。

Camera Capabilities 同样与 Provider 和导出隔离，只有用户在 Hardware Inventory 点击后才通过公开 AVFoundation discovery 读取一次本机 built-in/external 摄像头宣告的格式能力。它只显示当次序号、固定类型/位置/transport、格式数，以及有界的 encoded-pixel 分辨率、fps 范围、自动对焦和色彩空间；最多处理 32 个设备、每设备 256 个格式和 8,192 行合并能力。`NSCameraUseContinuityCameraDeviceType` 与 transport 双重过滤 Continuity Camera，Desk View 也不纳入。该路径不请求 Camera TCC、不打开设备、不创建 input/session/output，也不读取画面、unique/model ID、名称、厂商或当前配置；结果离页即清空。

Sound Input Check 是与设备清单隔离的 `publicTCC` 实验。它不在启动或自动采样时运行：首次按钮只显示用途说明，用户再次确认后才可能触发 macOS 麦克风授权。授权后的会话最长五分钟，停止、离页、音频配置变化或系统休眠都会释放输入流。每个 Float32 PCM buffer 只在音频回调内被即时归约为最多 128 个通道平均 min/max 波形分箱、全通道 RMS/峰值幅度和相对数字满刻度 1.0 的 dBFS；历史最多 300 点。频谱只对最近 256/512/1024/2048 帧中不超过当前 buffer 的最大固定窗口做去均值 Hann-window DFT，正频率归约为最多 128 个相对分箱，以当前非 DC 峰值为 0 dB、显示下限 −80 dB，且每秒最多更新 10 次。原始样本不离开回调，不保留、播放、写盘或导出，派生值也不进入 Snapshot/Diagnostics，离页清空。dBFS 不是 dBA、dB SPL 或校准响度；“最强非 DC 分箱中心”只是有限分辨率频点，不是声源、音高、语音或环境识别。

Camera Check 是另一个与相机能力清单隔离的 `publicTCC` 实验。Live 模式每次运行都要经过两步操作；只有第二次确认后才会在尚未决定时请求 Camera 权限，并只选择当次 discovery 中第一个通过 Continuity/Desk View 排除的本机 built-in/external 视频输入。预览最长两分钟，停止、离页、休眠、App 终止、设备断开或 capture session 中断/错误都会释放。32-bit BGRA raw frame 只在回调内以最快 10 Hz、每次最多 4,096 个规则采样点归约为相对数字 luma 与有界 frame-delivery 统计；整帧、pixel buffer 和 sample buffer 不离开回调，不录制、截图、识别、持久化或导出。相对 luma 不是 lux、曝光、环境/显示亮度或相机质量。当前源码与确定性 Demo/fixture 已完成；首次授权/拒绝和真实画面仍需用户在场验收。

慢 Provider 有独立的两秒协调等待边界；超时只让该模块降级，不会阻塞整页刷新，也不会在仍有同步读取占用时重复启动同一读取。

`capability` 旧字段仍保留，但新的访问级别不再把“需要 TCC”、“需要 entitlement”、“未文档化普通访问”和“私有实验接口”混成一类。硬件存在性、解码器、读取路径、数据流和用户功能也分别表达；详见 [`docs/07-硬件清单与能力语义.md`](docs/07-硬件清单与能力语义.md)。

## 安全与隐私

- 默认完全离线，不跟踪、不上传、不自动开始记录；
- 不以 root 运行，不调用 `sudo`，不写 SMC/SPU，不控制风扇或修改系统设置；
- 麦克风和相机权限分别只能由 Sound Input Check / Camera Check 内的用户二次确认触发；当前不请求定位、辅助功能、输入监控或完全磁盘访问；
- 不收集序列号、Hardware UUID、用户名、主机名、网络标识、USB 位置/路径、精确位置、进程列表、录音或相机画面；声音输入检查不保留 PCM，相机检查不保留帧，两者都不导出派生值；
- 不支持、权限不足、忙碌、超时和损坏数据会显示为状态，不用模拟值冒充读数。

私有/未文档化接口可能随机型和 macOS 变化。项目不是医疗、法定计量、工业安全或认证测量仪器。

## 本地构建

需要 macOS 14+ 和完成首次初始化的 Xcode：

```bash
swift build
swift test
./scripts/verify-local.sh
./scripts/build-app.sh release
open "outputs/Mac Sensor Lab.app" --args --demo
```

`scripts/verify-local.sh` 在本机完成格式、本地化、发布边界、Debug 构建、全部 XCTest、portable 自检和 Release App/Hardened Runtime 验证，不连接 GitHub。真机读取、Sanitizer 和 SPU 稳定性检查必须通过显式参数启用。GitHub Actions 仅保留手动触发，不会因 push 或 Pull Request 自动消耗分钟。

实时硬件自检与探针：

```bash
swift run sensorlab-selftest
swift run sensorlab-selftest --spu-stability
swift run sensorlab-probe
swift run sensorlab-probe -- --diagnostics
```

实时命令可能读取本机传感器并输出完整快照；提交公开 Issue 时只使用 App 主动生成、并经人工检查的 **Privacy-Safe Diagnostics**。

## 参与和文档

- 兼容性问题使用仓库的隐私安全 Issue 表单；安全问题使用 GitHub 私密漏洞报告；
- 新 Provider 必须有稳定且非识别性的 ID、单位/来源/失败路径、fixture 测试和明确的数据性质；
- 硬件清单、能力语义与导出 schema 见 [`docs/07-硬件清单与能力语义.md`](docs/07-硬件清单与能力语义.md)；详细边界与路线见 [`docs/05-当前实现与后续路线.md`](docs/05-当前实现与后续路线.md)；显示/NVMe、IOReport、Wi-Fi、Audio、USB 与 Camera 的实现/设计证据分别见 [`docs/08-显示校准与NVMe健康可行性.md`](docs/08-显示校准与NVMe健康可行性.md)、[`docs/09-IOReport普通权限可行性.md`](docs/09-IOReport普通权限可行性.md)、[`docs/10-Wi-Fi无线电边界.md`](docs/10-Wi-Fi无线电边界.md)、[`docs/11-Audio硬件清单边界.md`](docs/11-Audio硬件清单边界.md)、[`docs/12-USB设备清单边界.md`](docs/12-USB设备清单边界.md) 和 [`docs/13-Camera硬件清单边界.md`](docs/13-Camera硬件清单边界.md)；匿名跨机型流程见 [`docs/06-匿名兼容性贡献指南.md`](docs/06-匿名兼容性贡献指南.md)；
- 贡献规则、安全策略和第三方归属见 [`CONTRIBUTING.md`](CONTRIBUTING.md)、[`SECURITY.md`](SECURITY.md) 和 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

原创代码与图标使用 MIT 许可证；上游材料继续遵守各自许可证。
