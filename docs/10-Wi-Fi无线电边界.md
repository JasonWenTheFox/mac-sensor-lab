# 10 Wi-Fi 无线电读取与身份边界

更新：2026-09-08（E5a）

## 结论

标准 App 已加入 `connectivity.wifi_radio`，只读取当前默认 Wi-Fi 接口的公开 CoreWLAN 无线电状态。它提供 Layer 1 的固定原始事实和 Layer 2 的信号/噪声趋势，不扫描附近网络，也不读取网络或接口身份。

本轮没有添加 entitlement、Location usage description、TCC 请求、Helper 或私有框架。当前 Xcode 26.5 SDK 和一台测试 Mac 的普通用户无身份探针都证明所选 getter 可用；这仍不等于所有 Mac 和 macOS 组合都已实机验证。

## API 与字段矩阵

Apple 的 [`CWInterface`](https://developer.apple.com/documentation/corewlan/cwinterface) 是当前接口状态入口。本 Provider 只调用 `CWWiFiClient.shared().interface()` 以及下列 getter：

| 输出 | CoreWLAN 来源 | Nature | 失败处理 |
|---|---|---|---|
| Wi-Fi power | `powerOn()` | Raw | `false` 同时可能表示关闭或读取错误，摘要不会过度归因 |
| network service active | `serviceActive()` | Raw | `false` 表示未活跃或不可用 |
| associated radio link | `wlanChannel() != nil` | Derived | `nil` 只说明未报告关联频道，可能是未关联或读取错误 |
| RSSI | `rssiValue()` | Raw, dBm | 只接受 -120…-1；0 错误哨兵省略 |
| noise | `noiseMeasurement()` | Raw, dBm | 只接受 -140…-1；0 错误哨兵省略 |
| SNR | `RSSI - noise` | Derived, dB | 任一输入缺失或结果非法时省略 |
| channel / width / band | `wlanChannel()` | Raw | 只接受已知 band/width enum 和有界频道号 |
| PHY | `activePHYMode()` | Raw | 只显示 SDK 已知的 802.11a/b/g/n/ac/ax/be |
| transmit rate | [`transmitRate()`](https://developer.apple.com/documentation/corewlan/cwinterface/transmitrate%28%29) | Raw, Mbps | 0/非有限/异常值省略；这是协商 PHY 速率，不是应用吞吐量 |
| transmit power | `transmitPower()` | Raw, mW | 0 错误哨兵省略 |
| security | `security()` | Raw enum | 未知 enum 省略，不回显任意文本 |

Provider 保留 `publicOrdinary` 与 `documentedPlatformContract`：这描述 API 合约，而不是跨机型实测覆盖。若 CoreWLAN 没返回接口，`hardwarePresence` 保留 `unknown`，不会把一次 API 缺报解释为硬件一定不存在。

## 明确排除的身份与权限面

当前读取路径不调用 `ssid()`、`ssidData()`、`bssid()`、`countryCode()`、`interfaceName`、`hardwareAddress()`、IP 枚举、网络配置或 [`scanForNetworks`](https://developer.apple.com/documentation/corewlan/cwinterface/scanfornetworks%28withssid%3A%29)。因此 Snapshot、完整导出、隐私安全 Diagnostics、Demo、日志和 UI 都没有 SSID、BSSID、MAC/IP、接口名、国家代码、位置或扫描结果。

Apple 当前 SDK 对 SSID/BSSID/country code 明确写有 Location Services 与授权要求；[`Access Wi-Fi Information`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.wifi-info) entitlement 文档针对 `CNCopyCurrentNetworkInfo` 的当前网络身份访问。身份和扫描必须作为后续独立、用户主动的 E5b 设计，不得因为 radio getter 可读而静默开启。

## Layer 2 展示

Experiments 的 Wi-Fi Signal 面板复用 Dashboard 的有界内存历史：

- RSSI 与 noise 各自保留曲线和近期平均值；
- SNR 作为独立 Derived 通道保留；
- 当前频道、宽度、频段、PHY、协商发送速率、发送功率和安全模式保持逐字段展示；
- 不生成没有校准定义的“信号质量百分比”，不从 RSSI 猜距离，不把频道视图称为拥塞分析；
- 离开 App 后不留下额外 Wi-Fi 历史；只有用户主动使用现有完整 Snapshot/CSV 功能时才写入这些非身份数值。

## 后续门槛

E5a 不包含附近网络列表、频道占用、漫游记录或网络身份。若继续 E5b，必须先定义：显式用户动作、Location/TCC 前置说明、entitlement 与签名验证、遮蔽/导出策略、扫描超时与取消、频率限制、拒绝授权状态，以及“扫描结果不等于全部空口流量”的准确性说明。
