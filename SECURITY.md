# Security Policy

## Supported versions

项目仍处于首版开发阶段，仅当前主分支接受安全修复。

## Reporting a vulnerability

请使用 GitHub 仓库 Security 页中的 **Report a vulnerability** 私密报告入口。不要在公开 Issue 中发布漏洞细节、设备唯一标识、崩溃转储、录音、位置或其他私密数据；如果私密入口暂时不可用，请先暂停提交，而不是改用公开渠道。

普通跨机型兼容性问题可使用仓库的隐私安全 Issue 表单和 App 生成的最小化 Diagnostics JSON；完整快照、系统转储和真实读数不属于可公开附件。具体清单见 [`docs/06-匿名兼容性贡献指南.md`](docs/06-匿名兼容性贡献指南.md)。

## Security boundaries

Mac Sensor Lab 的首版不得：

- 让主 App 以 root 运行；
- 绕过 macOS 隐私或安全授权；
- 写入 Apple SPU 或 SMC 状态；
- 控制风扇；
- 静默启动录音、定位或其他受保护采集；
- 导出序列号、硬件 UUID、用户名、主机名或网络标识。

如果某个功能只能突破以上边界才能工作，它应当返回清楚的不可用状态，而不是自动降级到不安全实现。
