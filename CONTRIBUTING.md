# Contributing

感谢你帮助扩展 Mac Sensor Lab。首要原则是：测到什么就展示什么，无法验证的内容必须标注为实验性、估算或未校准。

## 开发流程

1. 使用 macOS 14 或更高版本和已完成首次设置的 Xcode；
2. 提交前运行不联网的 `./scripts/verify-local.sh`；需要真机、清洗器或 SPU 稳定性覆盖时分别添加 `--hardware`、`--sanitizers`、`--spu-stability`，或使用 `--all`；
3. 新传感器实现为独立 `SensorProvider`，使用稳定且不含机器标识的 Provider/Channel ID；
4. 明确来源、单位、原始或派生类别、权限和失败状态；
5. 为二进制解码、换算和导出补充纯 fixture 测试；
6. 不提交真实机器采样、`.work/` 上游克隆或 `outputs/` 构建产物。

连续 CSV 必须保持 `raw_value` 与 `formatted_value` 分离，具有可测试的文件上限，并在每批追加后同步。任何自动开始或静默长期记录都不会被接受。

任何校准或换算都必须保留原始通道，记录参考来源，并把缺少可追溯计量链的结果标为 `Estimated`。硬件“存在”不能当作实时 Provider 已经可用。

## 私有或未文档化接口

- 先记录固定上游 commit 和许可证；
- 禁止从无明确许可证的仓库复制代码或资源；
- 禁止增加静默提权、权限绕过、驱动状态写入、SMC 写入或风扇控制；
- 二进制依赖必须核验发布来源和 checksum，并在 Pull Request 中解释 Sandbox、签名与隐私影响；
- 新的权限提示只能由清楚的用户操作触发。

提交 Pull Request 前，请在描述中列出测试机型、macOS 版本、数据来源、已知范围和失败路径，不要公开序列号、UUID 或其他唯一标识。

## 匿名兼容性报告

跨机型测试请使用 GitHub 的 `Privacy-safe compatibility report` 表单，并遵循 [`docs/06-匿名兼容性贡献指南.md`](docs/06-匿名兼容性贡献指南.md)。如需附件，只上传由 App 主动导出的 Privacy-Safe Diagnostics JSON，并先在本地人工检查。

不要在公开 Issue 中粘贴完整 Snapshot/CSV、连续记录、`ioreg`、`system_profiler`、`sysdiagnose`、崩溃转储或真实读数截图。发现问题不等于获得公开设备信息的授权。
