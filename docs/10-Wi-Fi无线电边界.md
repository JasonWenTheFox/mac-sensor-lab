# 10 Wi-Fi 无线电读取与身份边界

更新：2026-09-09（E5a + E5b）

## 结论

标准 App 的 `connectivity.wifi_radio` 只读取当前默认 Wi-Fi 接口的公开 CoreWLAN 无线电状态，提供 Layer 1 固定事实和 Layer 2 信号/噪声趋势。E5b 另加一个不属于 Provider 的 Nearby Wi-Fi Channels 面板：只有用户阅读说明并二次确认后，才执行一次公开 CoreWLAN 非定向扫描，把结果立即缩减成无身份的频道摘要。

E5a/E5b 都没有添加 entitlement、Location usage description、Core Location 代码、TCC 请求、Helper 或私有框架。当前 Xcode 26.5 SDK 和一台测试 Mac 的普通用户无身份探针证明 E5a getter 可用；E5b 本轮只以 fixture 验证完整状态机和聚合，没有在开发机真实扫描周边网络，因此仍需用户主动完成第一次真机验收。这些证据都不等于所有 Mac 和 macOS 组合已验证。

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

## E5b 用户主动频道扫描

扫描仅调用 [`scanForNetworks(withName:includeHidden:)`](https://developer.apple.com/documentation/corewlan/cwinterface/scanfornetworks%28withname%3Aincludehidden%3A%29)，固定传入 `networkName: nil` 和 `includeHidden: false`；不发送定向 SSID probe，也不主动纳入 hidden 网络。对返回的 `CWNetwork` 只访问 `wlanChannel` 与 `rssiValue`，最多处理 512 条，按 band/channel 汇总：

- 报告记录数；
- 有效范围 -120…-1 dBm 内的 strongest / average RSSI；
- SDK 已知的 20/40/80/160 MHz 报告带宽；
- 固定 2.4/5/6 GHz band 与 1…1000 channel；
- 异常 band/channel 丢弃，非法 RSSI/width 省略，超过处理上限的数量单独报告。

扫描不会在启动、Provider 自动采样、刷新按钮、定时器、后台或离页后启动。按钮第一次点击只打开前置说明，第二次确认才开始；完成后冷却 10 秒。CoreWLAN 的公开 API 是同步阻塞调用且没有公开取消方法，因此 App 把调用放在后台任务：20 秒 watchdog 或“停止等待”只终止 UI 等待并丢弃迟到结果，不能虚假宣称已经中止系统扫描；底层调用返回前 `isOperationInFlight` 保持为真，拒绝重叠扫描，返回后才进入冷却。CoreWLAN 自己的 timeout、operation-not-permitted、unsupported 和其他错误映射为固定状态，不回显任意系统错误文本。

频道摘要是某一时刻收到的 advertisement scan records，不是设备数量真值，也不是全量空口流量、信道利用率、干扰、吞吐量或完整拥塞测量；墙体、发射功率、客户端位置、隐藏网络和未收到的帧都会影响结果。

## 明确排除的身份与权限面

E5a Provider 与 E5b scanner 都不调用 `ssid`、`ssidData`、`bssid`、`countryCode`、`informationElementData`、`interfaceName`、`hardwareAddress`、IP 枚举或网络配置。E5b 也不读取 `cachedScanResults`，不注册 `CWEventTypeScanCacheUpdated`，不使用内部依赖 SSID/BSSID 的 `isEqualToNetwork` 做应用级去重。`CWNetwork` 在映射后立即释放，应用状态只保留数值摘要。

Apple 当前 SDK 对 [`CWNetwork.ssid`](https://developer.apple.com/documentation/corewlan/cwnetwork/ssid)、[`CWNetwork.bssid`](https://developer.apple.com/documentation/corewlan/cwnetwork/bssid) 和 country code 明确写有 Location Services 与授权要求；[`CLLocationManager.requestWhenInUseAuthorization()`](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization%28%29) 是只能在 app in-use 时、带用途说明、异步通过 delegate 得到结果的用户授权流程。当前产品没有需要网络身份才能完成的用户价值，因此不请求这项权限。[`Access Wi-Fi Information`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.wifi-info) entitlement 的公开文档针对 `CNCopyCurrentNetworkInfo`，不能当作 CoreWLAN 身份/扫描的泛化授权替代。

Snapshot、完整导出、隐私安全 Diagnostics、连续记录、Demo fixture、日志和公开兼容性报告都没有 SSID、BSSID、MAC/IP、接口名、国家代码、位置或逐网络扫描结果。真实扫描摘要也不会流入这些路径；离开 Experiments 页面会立即清空面板结果。Demo 的扫描按钮只产生固定的非身份 fixture，不访问 Wi-Fi 硬件。

## Layer 2 展示

Experiments 的 Wi-Fi Signal 面板复用 Dashboard 的有界内存历史：

- RSSI 与 noise 各自保留曲线和近期平均值；
- SNR 作为独立 Derived 通道保留；
- 当前频道、宽度、频段、PHY、协商发送速率、发送功率和安全模式保持逐字段展示；
- 不生成没有校准定义的“信号质量百分比”，不从 RSSI 猜距离，不把频道视图称为拥塞分析；
- 离开 App 后不留下额外 Wi-Fi 历史；只有用户主动使用现有完整 Snapshot/CSV 功能时才写入这些非身份数值。

## 后续门槛

E5b 已交付无身份、用户主动的频道快照，但仍不包含附近网络名单、真实频道利用率/干扰、漫游记录或网络身份。除非后续出现必须以 SSID/BSSID 才能完成且值得 Location/TCC 成本的明确用户任务，否则保持身份路径关闭。若未来开启，必须另立 Epic 完成用途说明、前台授权状态机、拒绝/受限/系统关闭状态、签名能力核验、默认遮蔽、内存生命周期、导出 opt-in 和跨机型验收；不得顺手复用 E5b 扫描按钮扩大采集。
