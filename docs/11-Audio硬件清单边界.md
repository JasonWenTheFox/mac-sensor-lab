# 11 Audio 硬件清单与录音权限边界

更新：2026-09-10（E7a + E7b + E7c）

## 结论

标准 App 的 `hardware.audio` 使用公开 Core Audio HAL 属性查询，提供无需启动音频 IO 的 Layer 1/2 硬件清单：当前可见设备总数、可用设备数、输入/输出/双工能力数量，以及当前默认输入/输出的连接类别、通道数、标称采样率和设备级延迟。

该 Provider 不创建 IOProc、Audio Unit、Audio Queue、AVAudioEngine 或 capture session，不读取 PCM，不录音，也不调用麦克风授权 API。在一台测试 Mac 上以普通用户运行时为 Available，且没有出现 TCC 提示。

E7b/E7c 新增的 Sound Input Check 是与该 Provider 隔离的 `publicTCC` 面板。它仅在用户完成二次确认且授权后启动 `AVAudioEngine` input tap，并在音频回调内把 Float32 PCM 立即归约为受限元数据、波形包络、RMS/峰值幅度和 dBFS。原始样本不离开回调，没有录制、播放、持久化或导出路径；当前也没有 FFT 或物理声级估算。App Bundle 因此现在包含经审阅的中英文 `NSMicrophoneUsageDescription` 和 Hardened Runtime Audio Input entitlement；这不改变 `hardware.audio` 的普通权限属性。

## 公开 API 与固定输出

Apple 的 [`kAudioHardwarePropertyDevices`](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydevices) 返回系统当前可见的 AudioDevice 对象；默认输入/输出由同一系统对象的公开属性取得。每个句柄只在一次读取的局部内存中用于以下固定查询：

| 输出 | Core Audio 来源 | Nature | 边界 |
|---|---|---|---|
| `device_count` | `kAudioHardwarePropertyDevices` | Raw | HAL 设备数；可能包含虚拟/聚合设备，不等于物理硬件件数 |
| `alive_device_count` | `kAudioDevicePropertyDeviceIsAlive` | Raw | 只有全部设备都返回合法值时才发布 |
| input/output/duplex device count | [`kAudioDevicePropertyStreamConfiguration`](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertystreamconfiguration) 的 input/output scope | Raw/Derived count | 对每个方向汇总 `AudioBufferList` 的 channel；0-buffer 是合法的单向设备另一侧，不视为损坏 |
| default input/output present | `kAudioHardwarePropertyDefaultInputDevice` / `DefaultOutputDevice` | Raw | `kAudioObjectUnknown` 显示为未报告；查询失败与“无默认设备”分开 |
| default connection | [`kAudioDevicePropertyTransportType`](https://developer.apple.com/documentation/coreaudio/audiohardwareclock/transporttype) | Raw enum | 只映射 SDK 固定类别；未知值省略，不回显 FourCC 或驱动文本 |
| default channels | `kAudioDevicePropertyStreamConfiguration` | Raw | 只接受 0…1024，异常值省略 |
| default nominal sample rate | [`kAudioDevicePropertyNominalSampleRate`](https://developer.apple.com/documentation/coreaudio/audiohardwareclock/nominalsamplerate) | Raw, Hz | 这是设备当前配置的标称速率，不是实测时钟速率，也不是录音样本 |
| default device latency | `kAudioDevicePropertyLatency` | Raw, frames | 只表示 device latency；不含 stream latency 和 safety offset，不能直接当作端到端延迟 |

设备数量上限为 256；每个方向最多接受 256 个 buffer、1024 个 channel 和 64 KiB 的 stream-configuration payload。sample rate、latency、数组大小、整数相加和可变长度 `AudioBufferList` 都先做范围/布局校验。属性缺失或损坏时省略相应通道并把 Provider 降级为 Limited，不用 0 或模拟值补齐。

输入/输出/双工数量只有在所有已枚举设备的两侧配置都成功解析时才发布，避免局部失败被误报为“0 台”。默认设备可以随系统切换；Provider 每次读取都重新取得当前选择，不注册后台监听，也不为设备建立跨刷新身份。

## 身份与导出边界

Apple 对 [`AudioHardwareClock.uid`](https://developer.apple.com/documentation/coreaudio/audiohardwareclock/uid) 的公开说明明确指出：UID 跨重启持久，内容可能唯一到某个硬件实例或 CPU。因此 E7a 永久不查询或导出：

- device UID、model UID、clock UID 或任何 UID translation；
- 设备名称、厂商、图标、配置应用、clock domain、相关设备列表；
- AudioObject/AudioDevice 数字句柄、驱动自由文本或系统错误文本；
- PCM payload、音频片段、麦克风设备身份或正在播放内容。Sound Input Check 只显示当次会话的授权/生命周期状态、受限格式/计数元数据、最新波形包络和有界电平历史，并在离页时全部清除。

完整 Snapshot/JSON/CSV 只包含上述固定非身份字段。Privacy-Safe Diagnostics 仍只包含 Provider/Channel ID、状态和语义，不包含值、摘要、备注或来源。Demo 使用固定合成清单，不访问真实 Core Audio 设备。

连接类别和能力组合仍可能形成较粗粒度的设备环境特征，因此项目不会把它们与持久 UID、名称或其他机器标识拼接，也不会上传或自动记录。用户主动导出的完整 Snapshot 仍应在公开分享前人工检查。

## 权限边界

Apple 的[macOS 媒体采集授权说明](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)要求摄像头和麦克风采集在首次访问前取得用户授权，并为麦克风提供 [`NSMicrophoneUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription)。E7a 只读取 HAL 硬件属性，没有“先打开流再丢弃样本”的隐藏路径，因此仍归 `publicOrdinary`。

E7b/E7c 把 user-started PCM 作为独立 `publicTCC` 功能落地，实现边界如下：

- `AVCaptureDevice.authorizationStatus(for: .audio)` 是产品的 not-determined/authorized/denied/restricted 四态来源；
- 第一次“Start”仅打开 App 内用途说明；用户再次确认后，且当时状态仍为 not-determined，才调用 `requestAccess(for: .audio)`；
- denied/restricted 状态禁止开始，只能由用户在系统设置外部改变后手动重新检查；App 不打开或修改隐私设置；
- 获准后才创建 [`AVAudioEngine.inputNode`](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode) 输入路径并安装 1024-frame tap；只接受 Float32 format，样本率必须在 1…768,000 Hz，通道必须在 1…64，单 buffer 必须在 1…65,536 frames；
- tap 只在回调内读取一次 `floatChannelData`，拒绝空数据、非有限值、不一致结构、越界样本和超过 262,144 个分析样本的 buffer；原始样本不捕获到主线程或任何状态对象；
- 每个合法 buffer 输出最多 128 个 min/max 波形分箱；波形先对每帧各通道取平均，RMS 和峰值则覆盖所有通道样本，避免反相通道把能量指标抵消；
- dBFS 按 Apple vDSP 公开的[amplitude-to-decibels 公式](https://developer.apple.com/documentation/accelerate/vdsp/convert%28amplitude%3Atodecibels%3Azeroreference%3A%29-83uy1) `20 × log10(amplitude / 1.0)` 计算；精确数字静音显示 `−∞ dBFS`，图表仅为显示把低于 `−96 dBFS` 的值裁剪到下限。这不是 dBA、dB SPL 或经外部参考校准的响度；
- 会话总数上限为 1,000,000 buffers / 500,000,000 frames，电平历史最小间隔 80 ms 且最多 300 点，任一安全边界失败都先停流；
- 会话最长五分钟；Stop、离页、`AVAudioEngineConfigurationChange`、系统休眠、App 终止、格式变化或非法 buffer 均 fail closed，且 operation ID 使迟到的授权/音频回调无法重启已离开的会话；
- 停止时可在面板暂留计数和派生分析供阅读，离页时全部清除。任何状态、元数据或派生值都不进入 Provider、Dashboard history、Snapshot、Diagnostics、JSON/CSV、UserDefaults 或日志；
- `Info.plist` 和简体中文 `InfoPlist.strings` 包含精确、用户可见的用途文案；Hardened Runtime 签名只加入 Apple 文档化的 [`com.apple.security.device.audio-input`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input) entitlement。App 当前没有 App Sandbox，不混用 Sandbox microphone entitlement。

E7c 已在这条生命周期上完成 waveform/RMS/peak/dBFS。dBFS 与物理 dB SPL/dBA 永久分开，只有外部声级参考和独立校准设计后才能使用 Estimated/Calibrated 物理声级。FFT 在 E7d 单独评审频率分辨率、窗函数、采样率和性能上限。

## 失败与就绪语义

| 情况 | `status` | presence / readPath / feature |
|---|---|---|
| 完整固定字段可用 | Available | present / ready / ready |
| 局部属性缺失、布局非法、设备正在变化 | Limited | present 或 unknown / limited / partial |
| 系统明确返回 permission error | Permission required | unknown / permissionRequired / blocked；不自动弹框或引导开启麦克风 |
| 系统没有报告任何 AudioDevice | Unavailable | absent / ready / unsupported |
| 其他固定读取失败 | Error | unknown / failed / unknown |

`stream` 对此硬件清单始终是 `notApplicable`；它不表示麦克风或扬声器流已经启动。Sound Input Check 使用独立的 UI 会话状态，不伪造 Provider readiness。

## 验证范围

E7a fixture 覆盖：完整清单、不同默认输入/输出、合法 0-buffer 单向设备、无默认设备、空设备、未知 transport、越界 channel/sample-rate/latency、局部属性缺失、临时失败、权限拒绝和普通失败。源码回归禁止 UID/name/manufacturer 与音频启动/采集/授权 API。

E7b/E7c fixture 覆盖：明确二次确认前不请求权限/不启动、denied/restricted fail closed、授权请求未完成不伪称 denied、离页后迟到授权不得启动、格式改变后迟到 buffer 不得计入、五分钟上限/休眠中止、格式/启动失败、Demo 确定性合成分析且离页清空；还覆盖 RMS/峰值/dBFS 数学、反相通道、精确静音、非有限/越界输入、128 个波形分箱和 300 点历史上限。源码回归只允许分析器内唯一的 `floatChannelData` 读取，禁止其他 channel sample path、音频文件/录音 API、`tccutil`、UserDefaults 和系统设置打开路径。发布审计另外固定中英文用途文案、单一 entitlement、资源 lint 和签名 entitlement 验收。

本机无值验证只记录 `hardware.audio` 为 Available 及其固定 Channel ID，不记录设备数量、默认设备类型、采样率或延迟值。该证据证明当前开发机路径可读，不宣称所有驱动、虚拟设备和 macOS 版本都已验证。E7b/E7c 本轮没有触发真实 TCC 提示或读取真实 PCM；首次授权、拒绝后重试、真实 buffer/波形/电平和设备切换属于必须用户在场的手动验收。
