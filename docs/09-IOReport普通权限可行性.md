# 09 IOReport 普通权限可行性

更新：2026-09-08（E3 feasibility spike）

## 结论先行

- 当前 Apple Silicon 测试机上，普通用户进程无需 `sudo`、Helper、TCC 或系统设置变更，即可对三个精确白名单组完成 IOReport 发现、订阅、采样和 delta：CPU complex residency、CPU core residency 与 Energy Model。
- 这不使它成为公开 API。Apple SDK 公开的是 Kernel/DriverKit 的 IOReport 报告类型和驱动生产侧接口；`/usr/lib/libIOReport.dylib` 的用户态消费函数虽由 SDK stub 导出，但没有公开用户态头文件或 Apple Developer Documentation。项目将这条路径定为 **`privateExperimental`**。
- 当前标准 App/CLI 不链接 `libIOReport`，也没有新增 IOReport Provider。源码只加入不接触私有库的纯 metadata policy 与 delta math，以无真实读数 fixture 固化白名单、单位、reset/overflow 和身份过滤边界。
- Energy Model 的累计能量 delta 可以派生采样窗内的估算功率，但不是墙插整机功率；ANE 能量/功率不是 ANE utilization。CPU residency 可以做同一窗口内的比例，尚不能根据私有状态顺序安全发布真实频率。
- Media Engine、GPU DVFS 与内存带宽没有得到可核验的精确组、公开单位和跨机型证据，继续标为 Research Needed。不会扫描并输出所有私有通道名来“猜功能”。
- IOReport 与 `powermetrics` 是两条不同路径。本轮没有启动 `powermetrics`；不会因为另一个工具常用 root 就把当前普通权限结果改写成 Helper 需求。

## 1. API、来源与发行分类

### 1.1 Apple 提供了什么

Apple Developer Documentation 公开了 Kernel/DriverKit 的 [`IOReportFormat`](https://developer.apple.com/documentation/kernel/ioreportformat)、[`IOReportChannel`](https://developer.apple.com/documentation/kernel/ioreportchannel) 等报告结构。当前 SDK 的 `IOReportTypes.h` 还定义了 Simple、State、Histogram、SimpleArray format，以及 power/traffic/performance 类别；State 的底层结构记录进入次数与在本地 timebase 中累积的 ticks。

Apple 开源的 [XNU `IOUserServer.cpp`](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOUserServer.cpp) 展示驱动侧 `ConfigureReport` / `UpdateReport` 行为，[AppleSmartBattery.cpp](https://github.com/apple-oss-distributions/PowerManagement/blob/main/AppleSmartBatteryManager/AppleSmartBattery.cpp) 展示一个生产者如何定义 IOReport channel。它们都不能替代 App 侧消费 API 的公开合约。

当前 macOS 26.5 SDK 的 `libIOReport.tbd` 确实导出 `IOReportCopyChannelsInGroup`、`IOReportCreateSubscription`、`IOReportCreateSamples`、`IOReportCreateSamplesDelta`、Simple/State 取值和 metadata 函数；但 SDK 中没有相应用户态 header。E3 因而采用以下分类：

| 维度 | 结论 |
|---|---|
| 普通权限可达性 | 当前单机可达 |
| API 公开性 | 私有/未公开的用户态消费 ABI |
| 数据语义 | group/channel/unit 多数没有 Apple 合约 |
| 项目 Access | `privateExperimental`，不是 `publicOrdinary` 或 `undocumentedOrdinary` |
| Standard 构建 | 不链接、不注册 Provider、不隐式开启 |
| App Store | 不把该路径作为当前可发行能力 |
| Helper | 当前不需要，也不立项 |

许可清晰的交叉实现使用固定 commit 的 [exelban/stats](https://github.com/exelban/stats/tree/db5fee1eae913e24a7e0c4a0395092d867cf902d)（MIT）。本项目没有复制其完整实现；正式源码中的 policy 与 delta math 是独立、纯 Swift、无私有符号的安全边界。

## 2. 普通权限探针

### 2.1 不变量

探针位于被 Git 忽略的 `.work/`，不会进入产品或仓库历史。它只查询以下白名单：

1. `CPU Stats` / `CPU Complex Performance States`；
2. `CPU Stats` / `CPU Core Performance States`；
3. `Energy Model`，无 subgroup。

探针不调用 all-channels 枚举，不打印 group/subgroup/channel/state/unit 原文，不打印任何 counter、residency、能量或功率数值。输出仅包含发现稳定性、格式/类别计数、订阅与 delta 是否成功、正/零/负值数量。

测试环境为 arm64、macOS 26.5.2、Xcode 26.6、macOS SDK 26.5。它只提供 single-model evidence。

### 2.2 发现和采样结果

| 白名单组 | 连续 5 次发现 | 格式/结构 | 100/500/1000 ms | 语义结论 |
|---|---|---|---|---|
| CPU complex residency | 结构一致 | 6 个 State channel、87 个 state entry | 三种窗口均成功生成完整 delta；未见负 delta | delta 内状态标签有界可读，但 discovery 阶段标签不可用；没有可核验 unit label |
| CPU core residency | 结构一致 | 10 个 State channel、134 个 state entry | 三种窗口均成功生成完整 delta；未见负 delta | 每个 channel 见一个 allowlisted idle state；其余状态的跨机含义仍私有 |
| Energy Model | 结构一致 | 169 个 Simple channel | 三种窗口均成功生成完整 delta；未见负 delta | unit 均落入能量单位白名单，但只有 6 个 channel 落入当前 CPU/GPU/ANE/DRAM/PCI 分类 |

Energy Model 的 6 个候选包含 CPU、GPU、ANE、DRAM 各 1 个与 PCI 2 个。其余 163 个通道全部拒绝：数量多不代表可以从名字猜出 SoC、Media Engine、display 或 bandwidth 语义。

短窗口出现更多零 delta 是正常可能性；“成功创建 delta”也不保证每次都有活动。E3 没有把一次窗口中的正值数量或任何实际读数写入 fixture。

## 3. 逐能力决策

| 候选能力 | E3 证据 | 决策 |
|---|---|---|
| CPU core/complex residency ratio | 普通权限 delta 可读；idle 状态可窄白名单识别；绝对单位私有 | **Experimental candidate**；只能做同窗无量纲比例，先跨机验证 |
| CPU frequency / DVFS | 状态顺序存在，但固定上游需用机型频率表解释顺序 | **Research Needed**；不把 state index 冒充 MHz |
| CPU/GPU energy and power | 1 个 CPU、1 个 GPU 能量候选；单位可转 joule | **Experimental candidate**；delta/真实 elapsed 派生 Estimated W |
| ANE energy and power | 1 个能量候选 | **Experimental candidate**；只叫 ANE estimated power，永不除以假定最大功率冒充 utilization |
| DRAM power | 1 个能量候选 | **Experimental candidate**；与现有可选 SMC `memory_power` 分来源展示 |
| PCI energy/power | 2 个候选，说明一个 domain 可能有多个 counter | **Experimental candidate**；聚合规则需跨机 fixture，不能覆盖赋值 |
| GPU utilization | 当前已有独立 AGX allowlist Provider | IOReport 不重复实现；采样语义保持分开 |
| GPU frequency/residency | 本轮三个精确组没有可核验对应契约 | **Research Needed** |
| Media Engine activity/power | 163 个未分类 Energy channel 中可能存在相关事实，但没有白名单证据 | **Research Needed**；不按自由名称猜测 |
| Memory bandwidth / DCS | IOReport 白名单没有已验证 group；旧 `powermetrics` 上游路径已失效/停用该解析 | **Research Needed**；不发布带宽 |
| SoC/package total power | 不能证明白名单之和无遗漏、无重叠 | **Rejected as aggregate**；不得把分域简单求和叫整机功率 |

## 4. Counter、单位与失败策略

### Energy

- 只接受 `J`、`mJ`、`uJ`/`µJ`/`μJ`、`nJ`、`pJ`；未知、空白、控制字符或超长 unit 一律拒绝。
- 只接受非负 delta 和有限正 elapsed；`watts = delta × joulesPerCount / elapsedSeconds` 标为 Derived/Estimated。
- 负 delta 视为 counter reset、wrap、driver reload 或 schema mismatch；丢弃当前窗口并重建 baseline，绝不取绝对值或夹成零。
- 多 channel domain 必须检查求和溢出、单位转换与跨机聚合规则。E3 不宣称 PCI 两项必然可在所有机器相加。

### Residency

- `IOReportStateGetResidency` 的用户态语义未公开。即使底层类型记录 local-timebase ticks，也不推定私有库返回 ns。
- 只有同一 delta、同一 schema 内的非负 residency 可以计算无量纲占比；总和为零、负值或溢出就省略。
- `IDLE`、`DOWN`、`OFF` 是当前唯一 idle allowlist。未知状态不用于频率换算；channel/state 原名不进入 Snapshot、诊断、日志、持久化或导出。
- channel 数、state 数、顺序或结构变化会使旧 baseline 失效；睡眠/唤醒、驱动 reload 和系统更新后必须重新发现。

## 5. 与 `powermetrics` 的边界

[tlkh/asitop](https://github.com/tlkh/asitop/tree/74ebe2cbc23d5b1eec874aebb1b9bacfe0e670cd)（MIT）是一个明确的对照：它启动 `powermetrics`，并说明常规使用需要 `sudo`。其源码已经把旧 `bandwidth_counters` 解析从主流程注释掉，README 也说明 Apple 已从 `powermetrics` 移除 memory bandwidth。

这只证明那个 CLI 工作流的历史和权限边界，不证明 IOReport 用户态订阅需要 root，也不能把旧 DCS 字段移植成当前 IOReport schema。本项目没有运行、捆绑或解析 `powermetrics`。

## 6. 后续最多两个 Provider Epic

E3 的 decision gate 结论是“普通权限可读，但 API 和字段版本敏感”，所以只允许拆成实验候选：

1. **E3a Experimental Energy Model adapter**：独立 target/product，不成为 Standard App 的依赖；动态/链接失败安全降级，只输出固定 CPU/GPU/ANE/DRAM 候选，PCI 在聚合证据足够前继续省略。任何真机启用都必须显式、可见、可关闭。
2. **E3b Experimental CPU Residency**：至少取得第二种 SoC/macOS 的无值 schema fixture 后，先做 aggregate active/idle residency；真实 MHz 仍需独立、可复核的频率来源，不能从 index 猜测。

两个 Epic 都必须再次检查标准 App 二进制不含私有 IOReport import、没有任意 metadata 输出，并维持 `privateExperimental` 与 `singleModelObserved`。它们不是当前紧邻实现项；既定队列先回到 `storage.nvme_health` 首批公开 SMART 标量，再做 UInt128 和显示校准 core。

## 7. E3 验收

- SDK/runtime、Apple 一手生产侧资料、许可清晰上游与固定 commit 已核验；
- 精确白名单普通权限探针已完成，三种 sample duration 和五次发现稳定性已记录；
- 无真实值 fixture、metadata policy、unit/delta/reset/overflow 测试已加入；
- Standard 产品未链接 `libIOReport`，未新增 Provider、UI、Helper、`sudo` 或 `powermetrics`；
- CPU/GPU/ANE/DRAM 候选、频率、Media Engine、bandwidth 和 SoC total 的不同证据等级已拆开。
