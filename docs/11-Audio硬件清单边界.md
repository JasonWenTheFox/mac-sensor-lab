# 11 Audio 硬件清单与录音权限边界

更新：2026-09-09（E7a）

## 结论

标准 App 的 `hardware.audio` 使用公开 Core Audio HAL 属性查询，提供无需启动音频 IO 的 Layer 1/2 硬件清单：当前可见设备总数、可用设备数、输入/输出/双工能力数量，以及当前默认输入/输出的连接类别、通道数、标称采样率和设备级延迟。

该 Provider 不创建 IOProc、Audio Unit、Audio Queue、AVAudioEngine 或 capture session，不读取 PCM，不录音，也不调用麦克风授权 API。E7a 没有增加 `NSMicrophoneUsageDescription` 或 audio-input entitlement；在一台测试 Mac 上以普通用户运行时为 Available，且没有出现 TCC 提示。这个单机观察不等于未来 PCM 功能不需要权限：Apple 明确要求录音在首次访问麦克风前取得用户授权并声明用途。

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
- PCM、波形、音频片段、麦克风状态或正在播放内容。

完整 Snapshot/JSON/CSV 只包含上述固定非身份字段。Privacy-Safe Diagnostics 仍只包含 Provider/Channel ID、状态和语义，不包含值、摘要、备注或来源。Demo 使用固定合成清单，不访问真实 Core Audio 设备。

连接类别和能力组合仍可能形成较粗粒度的设备环境特征，因此项目不会把它们与持久 UID、名称或其他机器标识拼接，也不会上传或自动记录。用户主动导出的完整 Snapshot 仍应在公开分享前人工检查。

## 权限边界

Apple 的[macOS 媒体采集授权说明](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)要求摄像头和麦克风采集在首次访问前取得用户授权，并为麦克风提供 `NSMicrophoneUsageDescription`。E7a 只读取 HAL 硬件属性，没有“先偷偷打开流再丢弃样本”的隐藏路径，因此仍归 `publicOrdinary`。

未来 user-started PCM 是新的 `publicTCC` Epic，不能复用 E7a 的权限结论。它至少需要：

- 用户进入独立音频实验并明确开始后再解释和请求权限；
- denied/restricted/not-determined/authorized 的完整状态机；
- 离页、停止、设备切换、休眠和错误时释放音频流；
- 有界环形缓冲，默认不保存原始音频；
- dBFS 与物理 dB SPL/dBA 永久分开，只有外部声级参考后才能标为 Estimated/Calibrated；
- Developer ID、Hardened Runtime、entitlement、用途文案和多机型验收。

## 失败与就绪语义

| 情况 | `status` | presence / readPath / feature |
|---|---|---|
| 完整固定字段可用 | Available | present / ready / ready |
| 局部属性缺失、布局非法、设备正在变化 | Limited | present 或 unknown / limited / partial |
| 系统明确返回 permission error | Permission required | unknown / permissionRequired / blocked；不自动弹框或引导开启麦克风 |
| 系统没有报告任何 AudioDevice | Unavailable | absent / ready / unsupported |
| 其他固定读取失败 | Error | unknown / failed / unknown |

`stream` 对此硬件清单始终是 `notApplicable`；它不表示麦克风或扬声器流已经启动。

## 验证范围

E7a fixture 覆盖：完整清单、不同默认输入/输出、合法 0-buffer 单向设备、无默认设备、空设备、未知 transport、越界 channel/sample-rate/latency、局部属性缺失、临时失败、权限拒绝和普通失败。源码回归禁止 UID/name/manufacturer 与音频启动/采集/授权 API。

本机无值验证只记录 `hardware.audio` 为 Available 及其固定 Channel ID，不记录设备数量、默认设备类型、采样率或延迟值。该证据证明当前开发机路径可读，不宣称所有驱动、虚拟设备和 macOS 版本都已验证。
