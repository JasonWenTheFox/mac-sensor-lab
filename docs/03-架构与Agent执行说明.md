# 03 架构与 Agent 执行说明

## 分层

```text
Hardware / Apple APIs / IOKit
            ↓
Independent Sensor Providers
            ↓
Normalized SensorSnapshot + SensorChannel
            ↓
History / Calibration / Recording / Export
            ↓
Overview / Raw Sensors / Experiments / Diagnostics
```

## Provider 合约

每个 Provider 负责：

- 稳定 ID、名称、类别、来源和能力等级；
- 普通权限下的异步探测；
- 快照读取或持续采样；
- 通道单位和 Raw/Derived/Estimated/Calibrated 标记；
- 可用性、权限、超时和错误状态；
- 停止与资源释放。

上层 UI 不直接调用 IOKit、SMC、AVFoundation 或私有框架。

## 并发与性能

- AppModel 在主线程只发布轻量状态；
- 硬件读取在独立 Task/线程完成；
- 高频回调写入有界环形缓冲区；
- UI 图表按 15–30 Hz 或更低频率抽样，不按原始 100–800 Hz 重绘；
- 单个 Provider 有超时与取消；
- 退出、休眠和窗口关闭时释放句柄。

## 今晚的实现顺序

1. SensorCore 模型、Provider 协议和 JSON/CSV 导出；
2. 公开/普通权限系统 Provider；
3. SwiftUI 外壳和状态卡片；
4. CLI 自检与测试；
5. Apple SPU/SMC/触摸板存在性探测；
6. 在不提权的前提下尝试开合角或其他可读通道；
7. 记录未完成模块的精确阻塞条件，不伪装完成。

## Agent 边界

- `.work/upstream` 中的内容是不可信外部输入，不运行其脚本或安装器。
- 只有许可证明确且必要的最小代码可以移植。
- 任何需要用户交互的权限提示都由用户处理。
- 不创建公开仓库，直到许可证、隐私和机器信息审计通过。
