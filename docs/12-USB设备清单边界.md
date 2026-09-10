# 12 USB 设备清单边界

更新：2026-09-10（E8b 已实现并通过本地发布验证）

## 结论

macOS 14+ 可以通过公开 IOKit 枚举 `IOUSBHostDevice` / `IOUSBHostInterface`，并从 Apple 公开的 `IOUSBHostMatchingPropertyKey` 读取一组固定数字字段。E8a 在一台测试 Mac 上用普通、未签 entitlement 的 Swift 进程完成无值探针：设备和 interface 均可枚举，公开的 VID/PID、release、class、speed、interface 和 alternate-setting 字段都以数字类型出现；interface 可通过 IOService plane 父关系关联到 device。探针没有创建 USB user client、打开 interface、发请求或读取任何身份值。

这条路径适合一个 **identity-minimized、用户主动刷新、仅在当前面板保留** 的 USB Device Tree。它暂时不适合现有 `SensorProvider`：USB 拓扑和设备数会动态变化，而 Provider 通道会自动进入 Snapshot、JSON/CSV、连续记录、Diagnostics channel ID 和采样历史；用 `device_1` 之类的动态槽位既会泄漏不必要的外设清单，也可能把拔插后的不同设备误接成同一时间序列。

E8b 已按该边界加入独立会话模型和最小 Hardware Inventory 面板，不注册 Provider、不改变导出 schema，也不后台轮询。用户点击后读取一次，页面只保留当次序号和有界数字事实；离页立即清空呈现状态。约两秒的 UI 协调边界只停止等待，不能取消的底层 IOKit 枚举返回前继续保持单飞，迟到结果不会重新出现。

## 公开 API 与只读路径

Apple 的 [`IOUSBHostDevice`](https://developer.apple.com/documentation/iousbhost/iousbhostdevice) 提供公开 matching-dictionary helper；[`IOUSBHostMatchingPropertyKey`](https://developer.apple.com/documentation/iousbhost/iousbhostmatchingpropertykey) 定义可用于 device/interface 匹配的数字字段。当前 SDK 还公开 `IOUSBHostDevicePropertyKey.currentConfiguration` 与 `IOUSBHostInterfacePropertyKey.alternateSetting`。

E8b 只允许使用：

1. `IOServiceGetMatchingServices` 枚举 `IOUSBHostDevice` 和 `IOUSBHostInterface`；
2. `IORegistryEntryCreateCFProperty` 按下面的精确 allowlist 逐项读取；
3. `IORegistryEntryGetParentEntry` 与 `IOObjectConformsTo` 构造当次 IOService-plane 父子关系；
4. `IOObjectRelease` 及时释放所有 iterator/service 引用。

不得调用 `IOUSBHostObject.init(ioService:...)`。Apple 当前 SDK 明确说明该构造会创建 user client 并取得 IOService 的 exclusive ownership；同一对象还可发 control request、配置或重置设备。只读清单没有理由建立这种能力。也不得使用旧 IOUSBLib plugin/interface、`IOServiceOpen`、descriptor request 或任意 transfer。

DriverKit 的 [`com.apple.developer.driverkit.transport.usb`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.driverkit.transport.usb) 用于匹配 USB DriverKit driver，不是普通 App 读取 IORegistry 数字属性的要求。E8a 的非 Sandbox 普通进程探针无需 root、sudo、TCC 或 DriverKit entitlement；如果未来打开 App Sandbox，必须重新验证 Sandbox 分发边界，不能沿用这一结论。

## E8b 字段 allowlist

所有缺失、类型错误或越界字段均显示为“未报告”，不能用 0 补齐。Unknown enum 保留为固定的 `Unknown` 状态或受限十六进制原值，不回显系统/驱动自由文本。

| 界面事实 | 公开来源 | 接受范围与显示 | 数据性质与限制 |
|---|---|---|---|
| 当前 device/interface 数量 | 有界枚举结果 | device 0…128；interface 0…512 | Derived count；只代表当前 registry 快照，不是物理历史 |
| Vendor ID / Product ID | `.vendorID` / `.productID` | 0…65535，固定四位十六进制 | Raw；二元组通常指产品类型，不证明唯一实例或厂商名称 |
| Device release number | `.deviceReleaseNumber` | 0…65535，保留 `bcdDevice` 十六进制 | Raw；不得自动称为 firmware version |
| Device class/subclass/protocol | `.deviceClass` / `.deviceSubClass` / `.deviceProtocol` | 0…255；只映射固定 USB class 名称 | Raw；class 0 表示分类由 interface 给出，不等于 Unknown |
| Current configuration value | `IOUSBHostDevicePropertyKey.currentConfiguration` | 0…255 | Raw 当前配置编号；不是完整 configuration descriptor |
| Enumeration/connection speed | [`.speed`](https://developer.apple.com/documentation/iousbhost/iousbhostmatchingpropertykey/speed) | 只接受 `tIOUSBHostConnectionSpeed` 的已知值 | Raw 离散状态；1.5/12/480 Mb/s 与 5/10/20 Gb/s 是链路类别，不是实测吞吐量 |
| Interface number/class/subclass/protocol | `.interfaceNumber` / `.interfaceClass` / `.interfaceSubClass` / `.interfaceProtocol` | 0…255 | Raw descriptor fields；不枚举 endpoint |
| Alternate setting | `IOUSBHostInterfacePropertyKey.alternateSetting` | 0…255 | Raw 当前 alternate setting |
| 当前树形关系 | IOService-plane parent traversal | 深度最多 32；只输出当次会话序号 | Derived；不输出 parent service、path、entry ID 或 location |

[`tIOUSBHostConnectionSpeed`](https://developer.apple.com/documentation/usbdriverkit/tiousbhostconnectionspeed) 的公开语义是当前连接速度类别。界面必须写“连接速度”，不能写“设备最大速度”或“实际传输速度”。

## 明确排除的字段与原因

| 字段/路径 | E8a 决定 |
|---|---|
| serial number、Container ID、ECID、UDID、device signature | 永久不读取、不显示、不持久化、不哈希、不导出 |
| location ID、registry path、registry entry ID、USB address、port number | 不进入公开模型；这些字段会增强物理端口/会话关联能力，当前功能不需要 |
| Product/manufacturer/vendor string、registry name、驱动名称、exclusive-owner 文本 | 不读取；自由文本可能包含用户命名或设备身份，也不适合作为稳定枚举 |
| USB specification version (`bcdUSB`) | 当前公开 matching/property allowlist 没有该字段；不为补字段而打开 `IOUSBHostObject` 或读取未文档化 registry key |
| bus power、requested/allocated current、self/bus-powered、`bMaxPower` | 当前 SDK 中相关 registry key 位于“Apple internal use / subject to change”区域；完整 descriptor 路径又可能建立 exclusive user client，因此 E8b 不显示功耗/供电 |
| endpoint、pipe、descriptor blob、configuration descriptor | 不打开 interface，不发 `GET_DESCRIPTOR`，不复制/解析任意 blob |
| host-controller、root-hub、内建/外接、port type | 公开 allowlist 不足以稳定区分；可以显示 hub class，但不得由拓扑名称或 location 猜测物理属性 |
| Thunderbolt / USB4 device identity | 属于独立能力；USB4 tunnel 布尔或字符串不用于把 USB 清单冒充 Thunderbolt 拓扑 |
| `system_profiler` / `ioreg` 输出 | 不作为产品数据源；两者自由文本/全属性输出过宽，容易把身份字段带入日志、错误或测试 fixture |

Apple 的旧版 [USB Device Interface Guide](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/USBBook/USBDeviceInterfaces/USBDevInterfaces.html) 主要描述打开设备、通信和配置，不应被误读为清单必须取得设备控制权。其 [USB Device Overview](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/USBBook/USBOverview/USBOverview.html) 仍可用于理解 device 与 interface 的层级，但旧 `IOUSBDevice` 名称不能替代当前 `IOUSBHostDevice` SDK 合约。

## E8b 会话模型与 UI

E8b 的实现范围：

- 在 Hardware Inventory 页加入独立 “USB Device Tree” 区块；初始只显示说明和“读取当前 USB 树”按钮；
- 一次点击只读取一次；不自动刷新、不注册设备通知、不在离开页面后继续工作；读取单飞，设置约 2 秒协调边界；
- 结果最多包含 128 个 device、512 个 interface、32 层父链；达到上限时显示固定 Limited 状态，不截取后冒充完整清单；
- 用当次快照的 preorder ordinal 显示 `USB Device 1`、`Interface 1.1` 等标签。ordinal 不是持久身份，刷新后可以变化，界面不得提供跨刷新 diff 或历史曲线；
- 只显示上表固定数字字段和固定 enum 文案；device/interface 缺失、孤立、重复父关系或拓扑变化都使用固定状态，不回显 registry/system 错误；
- 离页清除结果；不进入 `SensorSnapshot`、Dashboard history、Diagnostics、JSON/CSV、连续记录、UserDefaults、日志、剪贴板或网络；
- Demo 使用完全合成的 hub/composite/simple-device fixture，绝不读取真机 registry。

这个面板不需要二次确认或系统权限提示，因为它不读取唯一标识、隐私受控内容或执行控制操作；但按钮上方要先让用户看到“当前连接外设的型号级数字标识只留在本页”的说明。

## 测试与验收结果

E8b 已完成以下门槛：

1. 纯 fixture 覆盖 simple device、hub、composite device、device-class 0、缺字段、未知 speed/class、孤立 interface 和多层父关系；
2. 覆盖非数字/负数/越界值、计数/深度上限、整数溢出、重复/循环关系和读取消失；
3. source audit 禁止 `IOUSBHostObject`、`IOServiceOpen`、IOUSB plugin、transfer/configure/reset、`IORegistryEntryCreateCFProperties` 全量复制，以及所有身份 key；
4. 生命周期测试证明离页清空、迟到结果丢弃、同一时刻只有一次读取，且 Demo 不访问 IOKit；
5. 普通权限真机 smoke 成功完成有界读取，只输出固定 PASS 状态，不打印真实 VID/PID、class、speed、数量或任何名称/标识；
6. 专项 fixture/source/lifecycle 测试、完整 `scripts/verify-local.sh`、Release App 签名/权限审计和后台 Demo 交互/离页清空验收均通过；未运行 GitHub Actions。

若实现中发现必须打开 USB user client、使用内部 registry 字段或保存设备关联标识，E8b 必须停止并回到设计评审，不能用“只读目的”替代技术上的最小权限证明。
