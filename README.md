# Mac Sensor Lab

简体中文 | [English](README.en.md)

一个事实优先、离线工作的原生 macOS 传感器查看与实验工具。

> **0.2.0 源码预览版**：仓库可以公开审查、克隆和本地构建，但目前没有面向普通用户的已公证下载包。`outputs/Mac Sensor Lab.app` 使用 ad-hoc 签名，仅供本机开发验证；正式二进制仍需 Developer ID 签名、公证和更多机型测试。

![使用确定性 Demo Provider 的 Mac Sensor Lab Overview](docs/images/overview-demo.png)

截图来自明确标识的 `--demo` fixture，不包含开发机的真实读数或机器标识。

## 它能做什么

Mac Sensor Lab 把能力分成三层，并在界面和导出中保留数据来源：

1. **原始事实**：系统性能、GPU、网络/磁盘汇总、电池/电源、热压力、显示、存储、只读 SMC、SPU 环境光/运动报告和上盖角度等 15 个独立 Provider。
2. **可理解展示**：状态、单位、来源、时间戳、Raw/Derived/Estimated/Calibrated 类型、历史曲线、搜索、JSON/CSV 快照和有上限的连续记录。
3. **实验解释**：水平/运动趋势、上盖量角器、光照校准、四通道环境光谱相对指纹、电池趋势、热压力、部件温度、系统功耗、网络和磁盘活动。

环境光谱指纹只比较四个未知响应通道的相对比例，可保存当前光型作为本地参考并显示相似度；它不会冒充色温、光谱波长或 lux。环境照度只有在用户提供外部 lux 参考并校准后才标为 `Estimated`。内部温度不是室温，内部功耗不是插座功率，1–10 秒采样也不宣称能分析振动频率。

慢 Provider 有独立的两秒协调等待边界；超时只让该模块降级，不会阻塞整页刷新，也不会在仍有同步读取占用时重复启动同一读取。

## 安全与隐私

- 默认完全离线，不跟踪、不上传、不自动开始记录；
- 不以 root 运行，不调用 `sudo`，不写 SMC/SPU，不控制风扇或修改系统设置；
- 当前版本不请求麦克风、定位、相机、辅助功能、输入监控或完全磁盘访问；
- 不收集序列号、Hardware UUID、用户名、主机名、网络标识、精确位置、进程列表或录音；
- 不支持、权限不足、忙碌、超时和损坏数据会显示为状态，不用模拟值冒充读数。

私有/未文档化接口可能随机型和 macOS 变化。项目不是医疗、法定计量、工业安全或认证测量仪器。

## 本地构建

需要 macOS 14+ 和完成首次初始化的 Xcode：

```bash
swift build
swift test
./scripts/verify-local.sh
./scripts/build-app.sh release
open "outputs/Mac Sensor Lab.app" --args --demo
```

`scripts/verify-local.sh` 在本机完成格式、本地化、发布边界、Debug 构建、全部 XCTest、portable 自检和 Release App/Hardened Runtime 验证，不连接 GitHub。真机读取、Sanitizer 和 SPU 稳定性检查必须通过显式参数启用。GitHub Actions 仅保留手动触发，不会因 push 或 Pull Request 自动消耗分钟。

实时硬件自检与探针：

```bash
swift run sensorlab-selftest
swift run sensorlab-selftest --spu-stability
swift run sensorlab-probe
swift run sensorlab-probe -- --diagnostics
```

实时命令可能读取本机传感器并输出完整快照；提交公开 Issue 时只使用 App 主动生成、并经人工检查的 **Privacy-Safe Diagnostics**。

## 参与和文档

- 兼容性问题使用仓库的隐私安全 Issue 表单；安全问题使用 GitHub 私密漏洞报告；
- 新 Provider 必须有稳定且非识别性的 ID、单位/来源/失败路径、fixture 测试和明确的数据性质；
- 详细能力、边界与路线见 [`docs/05-当前实现与后续路线.md`](docs/05-当前实现与后续路线.md)；匿名跨机型流程见 [`docs/06-匿名兼容性贡献指南.md`](docs/06-匿名兼容性贡献指南.md)；
- 贡献规则、安全策略和第三方归属见 [`CONTRIBUTING.md`](CONTRIBUTING.md)、[`SECURITY.md`](SECURITY.md) 和 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

原创代码与图标使用 MIT 许可证；上游材料继续遵守各自许可证。
