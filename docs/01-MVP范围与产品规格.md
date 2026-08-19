# 01 MVP 范围与产品规格

## MVP 成功定义

在当前 Apple Silicon Mac 上，用户能够打开原生 App，立即看到导航和传感器状态；数秒内得到至少一组真实、无需提权的系统/电源读数；能够区分可用、加载中、无权限、不支持和实验性状态；能够导出不含唯一标识的快照。

## 信息架构

### Overview

以卡片展示：

- System
- Power & Battery
- Thermals
- Display
- Storage
- Experimental Hardware

每张卡只显示关键指标和状态，不堆满跳动数字。

### Raw Sensors

按 Provider 分组展示：

- 通道名称和稳定 ID；
- 当前值与单位；
- 原始/派生/估算/校准标记；
- 数据来源和最后更新时间；
- 可用性、权限和错误详情。

### Experiments

首版显示可规划实验及其依赖状态。只有底层 Provider 可用且经过验证后才启用真正测量。

### About & Diagnostics

显示版本、构建信息、隐私说明、上游致谢、Provider 诊断和导出入口；不显示机器唯一标识。

## 交互要求

- 首屏不等待硬件枚举；
- Provider 独立异步加载；
- 可手动 Refresh；
- 失败状态给出原因和安全下一步，不提供 `sudo App` 之类快捷方式；
- 图表窗口默认保留最近 60 秒并降采样；
- UI 首版使用英文，代码和数据 ID 使用稳定英文；中文文档先完整保留。

## MVP 验收指标

- `swift build` 和 `swift test` 成功；
- CLI 自检输出合法 JSON；
- `.app` 能从 Finder/open 启动并显示窗口；
- 首次渲染不依赖慢速 Provider；
- 无权限或无设备时不崩溃；
- 导出不包含序列号、UDID、Hardware UUID、用户名或主机名；
- 所有显示值有单位、来源和数据性质；
- 第三方代码和参考项目许可证可追溯。
