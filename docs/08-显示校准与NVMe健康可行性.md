# 08 显示校准与 NVMe 健康可行性

更新：2026-09-08（E2b 设计 + E2c/E2d/E2e 实现节点）

## 结论先行

- 显示校准只应绑定本次 App 运行期内的显示器对象与当前显示模式；不持久化、不导出、不哈希 `CGDirectDisplayID`，也不尝试用 EDID、serial、ICC 名称或厂商/型号自动跨会话匹配。
- Apple 当前 Xcode SDK 公开了 `IONVMeSMARTInterface` 和 `NVMeSMARTData`。本机的无 `sudo` 、无标识符只读探针成功创建接口并读取 SMART 记录，因此基础 NVMe SMART 日志应优先归类为 **public ordinary**，不再默认假设需要 Helper。
- “接口是公开的”不等于“每台 Mac 都会返回所有字段”。正式 Provider 仍需无设备、接口创建失败、权限拒绝、离线、损坏值和跨机型 fixture。
- 不引入 `smartctl`，不解析 `system_profiler` 作为主路径，不为 SMART 新增特权 Helper，不构造单一的“SSD 健康分”。
- E2c/E2d 已按本页边界实现 `storage.nvme_health` 首批标量与十组 UInt128 累计计数，并在同一台 Mac 上通过不含读数/身份的 Diagnostics 真机验证。
- E2e 已实现不依赖 UI 的 session-only 显示校准 core；公开 state 不含显示 ID，水平几何、输入边界和 topology/mode 失效均有 fixture。E2f 才接入最小 ruler UI。

## 1. Display calibration slot

### 1.1 要解决的问题

CoreGraphics 的 reported physical size 可能是 72-DPI 推算，所以现有宽高、对角线和 PPI 必须继续标为 `Estimated`。物理尺子实验需要另一条用户明确参与的 `Calibrated` 路径，但不能为了保存校准而引入持久显示器指纹。

### 1.2 会话绑定模型

`DisplayCalibrationSession` 的实现采用以下边界：

| 字段 | 用途 | 持久/导出 |
|---|---|---|
| session-only `CGDirectDisplayID` | 在同一运行会话内把校准绑定到真实显示对象 | 永不持久、导出或记录 |
| `slotIndex` | 与当前 `display_1…display_16` 界面顺序对应 | 仅内存，不当作身份 |
| mode signature | pixels/points 宽高、rotation 和对应轴的 backing scale | 仅内存 |
| `topologyGeneration` | 显示器增删、重排或重建 slot 时使旧校准失效 | 仅内存 |
| `modeRevision` | 对应 slot 的 mode geometry 曾变化后使旧 ruler context 永久失效 | 仅内存 |
| axis | 首版只校准 horizontal；后续可独立加 vertical | 可进入不含身份的用户显式导出，但首版不导出 |
| reference length + rendered points | 用户用真实尺具对齐的输入 | 首版仅内存 |

当显示对象消失、`CGDirectDisplayID` 改变、对应显示模式的 pixels/points/rotation/backing scale 改变，或 slot 拓扑无法可靠重建时，core 会立即丢弃相关校准。拓扑增删/重排会重建全部 slot；单个 mode geometry 变化只清空该 slot。generation/revision 还会拒绝变化前取得的 context，即使之后恢复到相同 mode。刷新率或 HDR/EDR 状态单独变化不改变物理长度映射，不触发失效。

### 1.3 校准数学与输出语义

用户把屏幕上长度为 `renderedPoints` 的线段调整为现实中 `referenceMillimeters` 毫米：

```text
millimetersPerPoint = referenceMillimeters / renderedPoints
logicalPointsPerInch = 25.4 / millimetersPerPoint
axisPPI = logicalPointsPerInch * backingPixelsPerPoint
axisPhysicalMillimeters = currentAxisPoints * millimetersPerPoint
```

建议首版边界：

- `referenceMillimeters`: 10…2000 mm；
- `renderedPoints`: 20…20000 points；
- `millimetersPerPoint`: 0.01…10 mm/point；
- `backingPixelsPerPoint`: 0.25…8；
- `axisPPI`: 10…2000 ppi；
- 所有输入和派生值必须 finite，超界就拒绝，不夹取成“看起来合理”的数。

E2e core 只计算已校准水平轴的 `millimetersPerPoint`、logical points per inch、horizontal PPI 和物理宽度；不推断垂直边长或对角线。E2f UI 展示这些结果时必须标为 `Calibrated` 并注明“user-referenced, not certified metrology”。原有 System Estimated 通道保留，不被校准值覆盖；E2e 不新增 Snapshot/导出通道。

### 1.4 明确不做

- 不把 session slot 写进 `UserDefaults`；
- 不对 display ID 加盐/哈希后持久化，因为哈希仍是稳定身份；
- 不默认导入/导出校准；
- 不使用用户自定义显示器名称做自动匹配；
- 不因显示器型号相同就认为物理映射一致。

## 2. NVMe SMART 证据与访问路径

### 2.1 已核验证据

1. Apple Developer Documentation 公开列出 [`IONVMeSMARTInterface`](https://developer.apple.com/documentation/iokit/ionvmesmartinterface) 和 [`NVMeSMARTData`](https://developer.apple.com/documentation/iokit/nvmesmartdata)。
2. 本机 Xcode 26.5 SDK 的 `IOKit.framework/Headers/storage/nvme/NVMeSMARTLibExternal.h` 定义了 SMART-capable property、user-client/interface UUID、`SMARTReadData`、`GetIdentifyData` 和 `GetLogPage`。
3. 无特权临时探针只匹配 `NVMe SMART Capable` 服务，不调用 identify，不输出 registry name、BSD name、型号、serial、路径或实际健康值。结果为 1 个服务、1 个成功接口、1 次成功读取和 1 份通过基本值域检查的记录。这只是 single-model evidence，不是全平台兼容性承诺。
4. NVM Express [Base Specification 1.4b](https://nvmexpress.org/wp-content/uploads/NVM-Express-1_4b-2020.09.21-Ratified.pdf) 定义了 SMART / Health Information Log 字段、Data Units 单位/向上取整语义和默认 little-endian 编码；Apple header 明确引用 NVM Express 1.0c，当前 SDK 结构与这些基础字段一致。
5. macOS 自带 `system_profiler SPNVMeDataType -json` 在普通用户下可见 `smart_status`，但 schema 和语义没有稳定的公开编程契约，而且同一输出还包含被本项目禁止的设备标识字段。
6. [smartmontools](https://github.com/smartmontools/smartmontools/tree/a214aa796e8963279c3ed68389ed3d556d0f1a72) 在 Darwin 上也使用 NVMeSMARTLib，可作调用流程交叉证据；其许可证为 GPL-2.0-or-later，本项目不复制、链接或捆绑它。

### 2.2 逐字段可行性表

下表的 Access 说明读取路径；“实现决定”另行表达语义、数据模型或隐私门。

| 候选事实 | 标准语义 | Access 结论 | 实现决定 |
|---|---|---|---|
| SMART-capable service presence | Apple IOKit property 表示有可用 NVMe SMART user client | **Public ordinary** | 可作 presence/read-path，不当作 SMART 已读成功 |
| `CRITICAL_WARNING` raw byte | 多个 critical-warning bit 可同时置位 | **Public ordinary** | 首批；保留 raw bitmask，不压成“健康/不健康” |
| warning bit 0 | available spare 低于阈值 | **Public ordinary** | 首批 Derived boolean |
| warning bit 1 | composite temperature 超过 critical threshold | **Public ordinary** | 首批 Derived boolean |
| warning bit 2 | 介质或内部错误导致可靠性降低 | **Public ordinary** | 首批 Derived boolean，不自行推测原因 |
| warning bit 3 | media 进入只读模式 | **Public ordinary** | 首批 Derived boolean |
| warning bit 4 | volatile-memory backup 失败（仅有该能力时有意义） | **Public ordinary** | 首批 Derived boolean；其他 bit 只报 unknown-warning-present |
| `TEMPERATURE` | 控制器与 NVM 的 composite temperature，Kelvin | **Public ordinary** | 首批；值域检查后转 °C，严禁称为室温 |
| `AVAILABLE_SPARE` | 0…100% 剩余预留容量的归一化百分比 | **Public ordinary** | 首批 Raw |
| `AVAILABLE_SPARE_THRESHOLD` | 0…100% 预留容量告警阈值 | **Public ordinary** | 首批 Raw |
| `PERCENTAGE_USED` | 厂商依据用量和预测寿命给出的寿命已用估计；100 不等于已失效，可超过 100，255 是封顶表示 | **Public ordinary** | 首批 Raw/Estimated 语义；不计算 `100 - used`，不叫“Health %” |
| `DATA_UNITS_READ/WRITTEN` | 128-bit 计数；1 单位表示 1000 × 512 bytes，向上取整 | **Public ordinary** | E2d 已实现无损 Raw 十进制与独立 Derived 计数字节值；不声称为精确历史 I/O |
| `HOST_READ/WRITE_COMMANDS` | 128-bit 主机命令计数 | **Public ordinary** | E2d 已实现无损文本 Raw，不默认绘图 |
| `CONTROLLER_BUSY_TIME` | 128-bit，单位为分钟 | **Public ordinary** | E2d 已实现无损文本 Raw |
| `POWER_CYCLES` | 128-bit 通电周期计数 | **Public ordinary** | E2d 已实现无损文本 Raw |
| `POWER_ON_HOURS` | 128-bit 通电小时，不含控制器低功耗状态 | **Public ordinary** | E2d 已实现无损文本 Raw |
| `UNSAFE_SHUTDOWNS` | 掉电前未收到 NVMe shutdown notification 的计数 | **Public ordinary** | E2d 已实现；不把它解释为用户过错 |
| `MEDIA_ERRORS` | 控制器检测到的未恢复数据完整性错误次数 | **Public ordinary** | E2d 已实现；是累计事实，不是故障预测 |
| `NUM_ERROR_INFO_LOG_ENTRIES` | 控制器生命周期 Error Information log 条目数 | **Public ordinary** | E2d 已实现计数；仍不读详细 error log |
| 新版规范的温度传感器/告警时长/热管理字段 | 位于 Apple 当前 `NVMeSMARTData.RESERVED2` 区域 | **Public transport, research needed** | 不解码 reserved bytes；需版本、长度和跨机 fixture 后再立项 |
| `system_profiler` `smart_status` | Apple 系统报告的粗粒度文本 | **Undocumented ordinary** | 不作主路径或 fallback；避免不稳定 schema、进程开销和标识字段泄漏面 |
| `GetIdentifyData` 中的 serial/model/firmware/OUI | 控制器身份与版本 | **Public ordinary, privacy rejected** | serial/OUI 永久排除；首版整个 identify 调用不进行 |
| 详细 Error Information log | 可含 command/LBA 级错误上下文 | **Public transport, deferred** | 当前无足够用户价值，增加解码和隐私面；首版不读 |
| 上述基础 SMART 字段的 Helper 路径 | 同一批只读事实 | **Privileged helper not justified** | 当前普通权限路径已成功；不安装 Helper，不运行 `sudo` |

## 3. `storage.nvme_health` Provider 边界

以下第一批边界已在 E2c 实现，第二批已在 E2d 实现。

### 第一批：小而可证明

- 只针对系统卷所在的整盘；Disk Arbitration/BSD name 只允许在一次读取的局部内存中完成匹配，不进入 Snapshot、日志、诊断、导出或持久偏好。
- 只调用 `SMARTReadData`，不调用 `GetIdentifyData`、不读详细 error log、不发起 self-test 或任何写操作。
- 稳定通道候选：`critical_warning_bits`、五个已知 warning boolean、`unknown_warning_present`、`composite_temperature`、`available_spare`、`available_spare_threshold`、`percentage_used`。
- `percentage_used` 和 critical warning 始终分开展示；没有 recognized warning 只表示“本次未见标准已知告警位”，不是全面健康证明。
- SMART 是低频寿命/健康数据，Provider 内部应单飞并至少缓存 60 秒；不随 Dashboard 1 秒频率重复创建 user client。

### 第二批：无损累计计数

Apple header 将寿命计数表达为两个 `UInt64` 组成的 128-bit 数。现有 `SensorChannel.value` 是 `Double?`，不能无损承载 128-bit 整数。E2d 的实现是：

1. 建立两个 limb 的无损十进制转换与 fixture；
2. 原始计数以 `formattedValue` 的十进制文本导出，`value` 保持 `nil`；
3. 任何人类可读缩写只能作另一个 Derived/Estimated 展示，不能取代无损 Raw；
4. data units 的 bytes 换算使用检查式 128-bit 乘法，溢出时省略 Derived 但保留 Raw；该值是报告单位的精确换算，不是精确历史 I/O。

### 失败状态

| 情况 | 建议状态 |
|---|---|
| 系统整盘不是 NVMe，或明确没有 SMART-capable service | `unavailable` + hardware absent/unknown 语义 |
| user client/interface 不存在 | `unavailable`/read-path unavailable |
| `kIOReturnNotPrivileged` | `permissionRequired`；只记录固定错误分类，不自动转 Helper |
| offline/busy/temporary failure | `degraded`，保留最近成功样本时必须保留旧时间戳 |
| 长度、值域、reserved bit 或数学转换非法 | fail closed，省略字段或进入固定 `error`/`degraded` |

## 4. 权限、依赖与发行决策

- **Helper：暂不立项。** 只有多台受支持 Mac 证明公开只读路径因权限系统性失败，且固定字段的产品价值足够高，才能单独重开威胁建模。
- **`system_profiler`：不作 fallback。** 它可在普通用户下运行，但是输出 schema 未承诺、字段太粗、需额外子进程，并扩大身份字段过滤面。
- **smartmontools：不捆绑、不安装、不静默调用。** 它证明 Darwin 路径可行，但引入外部可执行文件会增加 GPL 分发、版本、安装位置和输出过滤负担，而本项目已有更小的公开 API 路径。
- **GitHub Actions：无需。** E2b 和后续实现优先使用本地 SDK、fixture 与 `scripts/verify-local.sh`。

## 5. E2b/E2c/E2d/E2e 验收与后续切片

E2b 的设计和证据目标已完成：显示校准不再需要持久身份，NVMe SMART 也不再被粗暴归为私有/特权能力。E3 随后完成 IOReport 普通权限可行性 Spike。E2c 已交付首批 SMART 标量、固定失败分类、至少 60 秒缓存和无身份真机诊断；E2d 已交付十组无损 UInt128 累计计数、Data Units 检查式换算和极值/溢出 fixture；E2e 已交付 session-only 显示校准 core、水平几何边界和精确失效 fixture。

E3 之后的显示/存储实现建议拆成独立节点：

1. [x] `storage.nvme_health` 首批标量和 warning bits；
2. [x] UInt128 无损计数模型与其余 SMART 累计事实；
3. [x] session-only Display calibration core，暂无 UI；
4. [ ] 最小水平 ruler 界面与失效提示，不进行视觉重构。
