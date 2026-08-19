# Contributing

感谢你帮助扩展 Mac Sensor Lab。首要原则是：测到什么就展示什么，无法验证的内容必须标注为实验性、估算或未校准。

## 开发流程

1. 使用 macOS 14 或更高版本和已完成首次设置的 Xcode；
2. 运行 `swift build`、`swift test` 和 `swift run sensorlab-selftest`；
3. 新传感器实现为独立 `SensorProvider`，使用稳定且不含机器标识的 Provider/Channel ID；
4. 明确来源、单位、原始或派生类别、权限和失败状态；
5. 为二进制解码、换算和导出补充纯 fixture 测试；
6. 不提交真实机器采样、`.work/` 上游克隆或 `outputs/` 构建产物。

## 私有或未文档化接口

- 先记录固定上游 commit 和许可证；
- 禁止从无明确许可证的仓库复制代码或资源；
- 禁止增加静默提权、权限绕过、驱动状态写入、SMC 写入或风扇控制；
- 二进制依赖必须核验发布来源和 checksum，并在 Pull Request 中解释 Sandbox、签名与隐私影响；
- 新的权限提示只能由清楚的用户操作触发。

提交 Pull Request 前，请在描述中列出测试机型、macOS 版本、数据来源、已知范围和失败路径，不要公开序列号、UUID 或其他唯一标识。
