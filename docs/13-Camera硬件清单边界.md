# 13 Camera 硬件清单与采集权限边界

更新：2026-09-11（E9a/E9b 清单完成；E9c Camera Check 实现完成、真机授权待验收）

## 结论

macOS 14+ 可以通过 Apple 公开的 [`AVCaptureDevice.DiscoverySession`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/discoverysession) 枚举当前可用的本机摄像头，并在不创建 capture input/session/output 的前提下读取受支持格式的分辨率、帧率范围、自动对焦类别和色彩空间。这些是设备声明的能力，不是实际画面、实测帧率、当前曝光或成像质量。

E9a 在一台测试 Mac 上用无 Camera entitlement、无 `NSCameraUsageDescription` 的 ad-hoc Hardened Runtime 探针完成了普通权限无值验证：固定类型 discovery 返回非空结果，所有受检格式通过有界结构校验，运行前后的 Camera TCC 状态相同。探针没有调用授权请求、创建输入或 capture session，也没有读取或打印设备身份和格式实际值。这是当前机器的可行性证据，不是所有机型、外接驱动和发行签名组合的保证。

E9b 已据此实现一个 **identity-minimized、用户主动、仅在当前 Hardware Inventory 页面保留** 的 Camera Capabilities 面板。它没有注册为自动刷新的 Provider，也不进入 Snapshot、Diagnostics、JSON/CSV、连续记录或持久化：摄像头列表会动态变化，格式矩阵本身也会增强设备指纹。

E9c 已把真正的 Camera Check 做成与清单、Provider 和导出完全隔离的 `publicTCC` 实验：它加入经过审阅的用途文案与 Camera entitlement，但只有用户在 Experiments 面板完成两步操作后才会请求或使用 Camera。预览最长两分钟，停止、离页、休眠、App 终止、设备断开、会话中断、运行错误或异常帧都会停止；真实首次授权、拒绝和画面仍待用户在场验收。

## 公开 API 与四条分界线

### 1. 设备发现

Discovery session 只使用以下固定条件：

- device types：`.builtInWideAngleCamera`、`.external`；
- media type：`.video`；
- position：`.unspecified`。

Apple 对 discovery 的说明强调设备类型列表是必填项，目的是避免未来新增的设备类型自动混入现有 App。E9b 不使用已弃用的全量 `devices()`、按 unique ID 反查、默认设备或系统/用户偏好摄像头，也不注册连接变化通知或 KVO；每次用户点击只获取一个当前快照。

### 2. 支持格式元数据

每个发现结果只读取公开 [`formats`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/formats)。每个 [`AVCaptureDevice.Format`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format) 是不可变的支持格式描述；E9b 只从中取得：

- `formatDescription` 经 [`CMVideoFormatDescriptionGetDimensions`](https://developer.apple.com/documentation/coremedia/cmvideoformatdescriptiongetdimensions(_:)) 得到的 encoded-pixel 宽高；
- `videoSupportedFrameRateRanges` 的最小/最大 fps；
- `autoFocusSystem` 的固定枚举；
- `supportedColorSpaces` 的固定枚举。

这些值只描述设备宣告“支持什么”。E9b 不读取或修改 `activeFormat`、active frame duration、focus/exposure/white-balance 当前状态或任何可设置属性，也不调用 `lockForConfiguration()`。

### 3. Camera TCC

Apple 把 [`authorizationStatus(for:)`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:)) 与 [`requestAccess(for:)`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:)) 分开：前者读取状态，后者在需要时请求用户权限。当前 SDK 还明确说明，在 not-determined 状态创建 `AVCaptureDeviceInput` 会自动显示授权对话框。

Camera Capabilities 路径连授权状态也不读取，更不得调用授权请求或创建 input。E9c 为独立 Camera Check target path 加入 `NSCameraUsageDescription` 与 Apple 的 [`com.apple.security.device.camera`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.camera) entitlement；这不改变清单自身的无提示、只发现边界。若某个系统/签名组合拒绝纯 discovery，清单仍显示固定的不可用/受限状态，不得把触发 TCC 当作静默回退。

### 4. 图像采集

以下任一行为都不属于 E9b 清单；E9c 只能在后文固定的独立 Camera Check 边界内使用其中最小子集：

- 创建 `AVCaptureDeviceInput`、`AVCaptureSession` 或任何 capture output/preview；
- 启动、预热或保持视频流，即使立即丢弃帧；
- 取得 pixel buffer、照片、视频、深度、元数据或音频；
- 计算亮度、清晰度、颜色、帧率、曝光、运动、人脸或其他画面统计；
- 录制、截图、写盘、导出、上传或后台使用摄像头。

不得把 E9a 的无提示 discovery 证据外推到 capture。E9c 因此另行加入用户可见目的、每次运行的两步启动、四态 TCC、两分钟最长生命周期、停止/离页/休眠释放和“完全不提供录制/截图”的源码审计；真实授权和画面必须独立验收。

## Continuity Camera 隔离

当前 SDK 明确指出：若 App 未加入 `NSCameraUseContinuityCameraDeviceType = true`，Continuity Camera 在 macOS 上可能把 `deviceType` 报成 `.builtInWideAngleCamera`。因此仅仅“不查询 `.continuityCamera`”仍不足以排除附近 iPhone。

E9b 必须同时满足：

1. 在 Info.plist 加入 `NSCameraUseContinuityCameraDeviceType = true`，仅用于让系统报告独立类型；这不是 Camera TCC 用途文案；
2. discovery allowlist 不包含 `.continuityCamera` 或 `.deskViewCamera`；
3. 读取固定 transport enum 作为第二道防线，遇到 Continuity Capture wired/wireless 或旧版 legacy 类别时丢弃该设备，不显示、不计数；
4. 不读取 Continuity 设备、关联设备、设备名称或连接通知，不尝试唤醒/配对附近设备。

如果未来要支持 Continuity Camera，应作为单独的用户主动功能重新评审；不能悄悄扩大 E9b。

## E9b 字段 allowlist

所有输出都使用当次快照序号。缺失、未知、非有限或越界字段必须省略或使局部结果 Limited，不能用 0 或模拟值补齐。

| 界面事实 | 公开来源 | 接受范围与显示 | Nature 与限制 |
|---|---|---|---|
| 当前支持的本机摄像头数量 | discovery `devices` | 0…32 | Derived count；不包含显式排除的 Continuity/Desk View，不等于历史设备数 |
| Camera 1…N | 本次有界结果顺序 | 1…32 | Derived session ordinal；不跨刷新建立身份 |
| 类型 | `deviceType` | Built-in wide-angle / External 两种固定标签 | Raw enum；不是型号名称 |
| 位置 | `position` | Unspecified / Front / Back | Raw enum；macOS 常见 Unspecified 不是错误 |
| 连接类别 | `transportType` | 只映射 SDK 固定类别；未知显示 Unknown，不回显 FourCC | Raw enum；同时用于拒绝 Continuity transport |
| 原生格式数量 | `formats.count` | 0…256 / device | Raw count；多个 pixel-format 变体可能具有相同分辨率/帧率 |
| 格式分辨率 | `formatDescription` dimensions | 每轴 1…32,768 encoded pixels | Raw；不是裁切后视场、照片尺寸或画面质量 |
| 帧率范围 | `videoSupportedFrameRateRanges` | finite 且 `0 < fps <= 1,000`；最多 32 ranges / format | Raw capability；不是当前或实测 fps |
| 自动对焦系统 | `autoFocusSystem` | None / Contrast detection / Phase detection / Unknown | Raw enum；不是当前焦点、对焦成功率或镜头状态 |
| 色彩空间 | `supportedColorSpaces` | macOS 固定 sRGB / P3 D65 / Unknown；最多 8 项 | Raw capability；不等于当前输出色彩空间、HDR 或显示器色域 |

展示层可以把完全相同的 `(width, height, minFPS, maxFPS, autofocus, colorSpaces)` 行合并并显示受限的 variant count，但不能把离散范围合并成虚假的连续区间。格式列表总量上限为 8,192 行，任何整数累加和排序键都必须检查溢出。

## 明确排除的字段

| 字段或路径 | 决定 |
|---|---|
| [`uniqueID`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/uniqueid) | 永久不读取、不显示、不哈希、不持久化；Apple 明确其跨连接、App 重启和系统重启保持稳定 |
| `modelID` | 当前排除；虽然是型号级而非实例唯一，但仍是持久 identifier，格式能力已能提供目标价值 |
| `localizedName`、`manufacturer` | 不读取自由文本；外接/虚拟设备可能含用户或驱动命名 |
| `userPreferredCamera`、`systemPreferredCamera`、default camera | 不读取；会暴露用户选择/系统决策并引入跨刷新身份 |
| linked/constituent devices、input sources | 不读取；可能扩大到麦克风、物理子设备和更多身份字段 |
| `isInUseByAnotherApplication`、suspended/adjusting/current state | 不显示；这是其他 App 活动、隐私遮挡或当前捕获状态，不是静态硬件清单 |
| media subtype/FourCC、format extensions | E9b 首版排除；不回显任意 descriptor 扩展或驱动数据，可在固定 codec allowlist 有明确用户价值后再评审 |
| active format、frame duration、focus/exposure/WB/zoom | 不读取或设置；它们是当前运行配置，不代表完整硬件能力，部分设置还要求独占配置锁 |
| FOV、binning、HDR、ISO、曝光范围、稳定模式 | 当前 macOS SDK 对这些常见移动端 `AVCaptureDeviceFormat` 属性标为 unavailable，不能用 iOS 资料或猜测补齐 |
| 错误描述、debugDescription、对象 description | 不回显；只映射项目固定失败类别 |

## 会话模型与失败语义

E9b 已复用 USB tree 验证过的 session-only 交互形态，并使用独立模型和 source：

- 初始只显示数据边界与“读取摄像头能力”按钮；不会在 App 启动、自动采样或页面出现时枚举；
- 后台执行一次同步 discovery/reduction；同一 source 单飞，约两秒的 UI 等待边界只停止等待，不能取消的底层工作返回前不得叠加新任务；
- operation ID 使停止等待、离页或新一轮读取后的迟到结果无法重新出现；
- 页面离开时清空设备、格式、计数、状态和错误；不注册长期通知、timer 或 KVO；
- 界面 Demo 只使用 built-in / external 合成 fixture，malformed / overflow 由 reducer fixture 覆盖；Demo 不访问 AVFoundation；
- 固定状态至少区分：ready、no supported local camera、timed out waiting、malformed/over-limit data、ordinary discovery unavailable。不得把空结果写成“Mac 没有任何摄像头”，因为 Continuity Camera 被有意排除。

## E9b 验收门

实现节点必须同时具备，E9b 当前均已满足：

1. pure reducer fixture：0/1/多设备、重复格式、未知 enum、0/越界 dimensions、非有限/倒置 fps、32/256/32/8/8,192 上限和累加溢出；
2. source audit：只允许 discovery、固定 properties 和 CoreMedia dimensions；拒绝所有 identity/free-text、authorization、input/session/output/preview、active/configuration、frame/pixel-buffer API；
3. 当时的 release audit 要求 Continuity 类型键为 true，并在 E9c 前继续拒绝 `NSCameraUsageDescription` 和 Camera entitlement；E9c 完成后改为精确固定 Camera 用途文案与 entitlement，同时保持清单 source 不得触碰 TCC/capture；
4. UI lifecycle fixture：显式点击、单飞、等待边界、迟到丢弃、重读替换、离页清空和 Demo 不接触 AVFoundation；
5. 普通权限无值 smoke：只报告结构数量/边界与 Camera TCC 状态未变化，不记录设备类型分布、分辨率、fps、名称、ID 或其他真实值；
6. 完整 `scripts/verify-local.sh` 和后台 Demo 启动/交互；不运行 GitHub Actions。

当前新增 10 项 reducer/source/lifecycle 测试，覆盖空结果、重复能力合并、未知/异常字段、Continuity/Desk View 双重排除、全部数量上限、单飞、重读替换、固定失败态、两秒等待边界、迟到丢弃与离页清空。无 Camera entitlement/用途文案的 ad-hoc Hardened Runtime 无值 smoke 直接调用产品 `CameraInventoryReader`，只报告结构计数并确认 Camera authorization state 前后不变；后台中文 Demo 已验证按钮读取、折叠明细和离页清空。157 项 XCTest、26 Provider portable contract、Release/Hardened Runtime 与发布边界审计全部通过，未运行 GitHub Actions。

## E9c Camera Check 实现边界

### 用户意图与 TCC

- Live 模式每次运行都必须经过两步：首次按钮只显示 App 内隐私说明，第二次确认才继续；即使 Camera 已授权，也不能把下一次运行缩成自动启动或页面出现即启动。
- 四态保持独立：`notDetermined` 只在第二次确认后调用 `requestAccess(for: .video)`；`authorized` 才能创建 input/session/output；`denied` 与 `restricted` 不尝试 capture，也不修改系统设置。
- English purpose：`Mac Sensor Lab uses camera input only while you run Camera Check. Frames stay in memory for live preview and bounded analysis and are never saved or exported.`
- 简体中文用途：`Mac Sensor Lab 仅在你主动运行相机检查时使用摄像头。画面只在内存中用于实时预览和有界分析，不会保存或导出。`
- Hardened Runtime entitlement 只能是已审阅的 Audio Input 与 Camera 两项；Camera Capabilities 自身仍不检查状态、不请求权限、不创建 capture 对象。

### Capture allowlist

Camera Check 只允许以下路径：

1. 固定 discovery：`.builtInWideAngleCamera` / `.external`、`.video`、`.unspecified`；按 type 与 Continuity Capture wired/wireless/legacy transport 再过滤一次，取当次第一个受支持本机输入，但不读取或显示名称、ID、型号或用户默认选择；
2. `AVCaptureDeviceInput` + 单个 `AVCaptureSession` + 单个 `AVCaptureVideoDataOutput`；只用 `.medium`，不支持时降为 `.low`，不锁定或修改设备配置；
3. 输出固定请求 32-bit BGRA，并设置 `alwaysDiscardsLateVideoFrames = true`；`startRunning()` 在专用串行队列执行，不能阻塞主线程；
4. 单个 `AVCaptureVideoPreviewLayer` 只展示当前会话，不提供截图、暂停帧、保存或分享；
5. 观察 Camera disconnect、session interruption/runtime error、Mac sleep 和 App terminate；任一事件都 fail closed，不自动重启。

明确禁止 `AVCapturePhotoOutput`、movie/file output、audio/metadata/depth output、Asset Writer、Vision、人脸/物体/生物特征识别、网络上传、设备配置锁、active format 修改、默认/偏好摄像头、unique/model ID、名称、厂商和自由文本错误回显。

### Raw frame 归约与真实性

- `CMSampleBuffer` / `CVPixelBuffer` 只存在于 AVFoundation delegate 回调；代码只以 read-only 方式锁定 base address，并在同一调用栈解锁。它不把整帧复制成 `Data`、数组、图片或 model 字段，也不跨 callback 保留 buffer。
- 每次分析每轴最多接受 8,192 pixels、row bytes 最多 65,536、buffer 最多 512 MiB；实际 `.medium/.low` 会远低于这些 fail-closed 解析上限。
- 分析 cadence 最快 10 Hz；每帧采用规则网格，最多读取 4,096 个 BGRA pixel，立即归约为采样数、相对数字 luma 的 mean/min/max。UI 只展示 mean 和 max−min span。
- luma 使用 gamma-coded RGB 的固定加权数字统计，范围 0…1；它不是 lux、曝光、环境亮度、显示亮度、动态范围或相机质量，也不做自动阈值结论。
- delegate 只保留计数、上次分析时间和回调；model 最多保留最新一份派生 observation 与相邻 observation 推导的 frame-delivery rate，不保留图片历史。
- 最多接受 100,000 个 delivered/drop 计数与 20,000 份分析 observation；异常尺寸、格式、缓冲区、倒退/重复计数、时间倒退、非有限值或超限都会停止。

### 生命周期和 Demo

- 会话最长 120 秒；手动 Stop 立即使 callbacks 失效、移除 delegate/observer、清空 preview handle，并在 session queue 停止数据流。派生数值可保留在当前面板直到离页，离页全部清空。
- operation ID 使授权、启动、帧和终止的迟到 callback 无法复活已停止/已离页的会话；启动过程中 Stop 也会让 delegate 先失效，排队的 session 启动随后立即停止。
- Demo 使用确定性合成统计和明确标识的合成预览，不读取授权状态、不 discovery、不创建 capture session 或访问 Camera。
- Camera Check 继续不进入 Provider、Dashboard 自动采样、Snapshot、连续记录、Diagnostics、校准、持久化或导出。

## E9c 验收门

无需用户在场的部分必须通过：

1. pure analyzer fixture：黑/白/常量 BGRA、row/buffer/dimension 越界、最多 4,096 采样和浮点舍入边界；
2. model fixture：已授权仍需二次确认、not-determined 只在确认后 request、denied/restricted/incomplete、最长时限、生命周期终止、倒退计数、迟到授权/帧、失败映射、Demo 清空；
3. source/release audit：清单 source 继续拒绝 Camera TCC/capture；Camera Check source 只允许固定 capture 子集并拒绝 identity、录制、识别、配置和上传；用途文案、两项 entitlement 与 App 签名精确匹配；
4. 完整 `scripts/verify-local.sh` 与后台中文 Demo UI；不运行 GitHub Actions，不启动 live Camera Check。

仍必须等用户在场的部分：首次 `notDetermined → authorized/denied` 系统提示、已拒绝后的重新检查、真实 built-in/external preview、绿灯、Stop/离页/休眠释放、真实帧统计合理性，以及至少第二台 Mac/外接相机兼容性。完成这些前，E9c 只能称为“实现完成、真机验收待定”，不能作为已验证的普通用户二进制能力。

## 遗留事项

- E9b：已按本文件实现 session-only Camera Capabilities；只做了功能需要的最小 Hardware Inventory 面板，没有进行 UI 美化。
- E9c：Camera TCC、purpose string、entitlement、两步启动、两分钟生命周期、预览、帧归约/销毁、fixture 与审计已实现；首次授权/拒绝和真实画面验收仍等待用户在场。
- exposure、实际 fps、亮度/清晰度等画面层指标只有 E9c 获得实时帧后才有意义；不得由静态格式能力伪造。
- Camera 型号名称、unique/model ID、Continuity Camera、Desk View、录制、照片、音频、深度、人脸/生物识别和后台捕获继续不在当前范围。
