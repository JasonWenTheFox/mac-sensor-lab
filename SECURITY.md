# Security Policy

## Supported versions

项目仍处于首版开发阶段，仅当前主分支接受安全修复。

## Reporting a vulnerability

公开仓库建立前，请不要创建包含设备唯一标识、崩溃转储、录音、位置或其他私密数据的公开 Issue。仓库发布后会在此补充私密报告渠道。

## Security boundaries

Mac Sensor Lab 的首版不得：

- 让主 App 以 root 运行；
- 绕过 macOS 隐私或安全授权；
- 写入 Apple SPU 或 SMC 状态；
- 控制风扇；
- 静默启动录音、定位或其他受保护采集；
- 导出序列号、硬件 UUID、用户名、主机名或网络标识。

如果某个功能只能突破以上边界才能工作，它应当返回清楚的不可用状态，而不是自动降级到不安全实现。
