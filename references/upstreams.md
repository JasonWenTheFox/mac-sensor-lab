# 上游项目与复用边界

核验时间：2026-08-20。所有仓库仅浅克隆到 `.work/upstream/` 供分析，正式源码不直接包含嵌套仓库。

| 项目 | 固定 commit | 许可证 | 当前用途 |
|---|---|---|---|
| [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer) | `203685640287449eaecf521c24d1f5e52486ecb7` | MIT | Apple SPU HID 报告格式、IMU/ALS/开合角参考 |
| [KrishKrosh/TrackWeight](https://github.com/KrishKrosh/TrackWeight) | `e322cae241d29afbee2860a6b585e9fe3974bd0c` | MIT | 触摸板称重工作流与稳定性参考 |
| [Kyome22/OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) | `15c6bb0c6a2d2858559493a28ab23f7ac58648a3` | MIT | 原始触点、压力、面积与状态 API 参考；依赖私有框架和二进制 XCFramework |
| [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) | `f7e4e5cb46fe13a518091ce5d47f0ec2e3fecd80` | Apache-2.0 | 原生 Swift IOKit 开合角设备探测和 feature report 参考 |
| [exelban/stats](https://github.com/exelban/stats) | `db5fee1eae913e24a7e0c4a0395092d867cf902d` | MIT | SMC、HID 温度、电压、电流和 IOReport 功耗参考 |
| [pirate/mac-hardware-toys](https://github.com/pirate/mac-hardware-toys) | `5ed3c81540e214e1d1f99160d9c3c0446a7db506` | **未发现仓库级明确许可证** | 只研究产品思路；禁止复制代码或资源 |

## 补充 Swift 实现调查

以下仓库规模和使用量较小，仅用于交叉核对，不直接作为首版依赖：

- `vnixx/apple-silicon-accelerometer` commit `7153f022c2a419f8e655c2d58e42c42e8f5817e0`，MIT；
- `kuaner/apple-silicon-accelerometer` commit `855d3658a2e6abab64bbaaf9198a6795ced03e8a`，MIT；
- `Kireyin/AppleSiliconAccelerometer` commit `bc9be79341e7d295b48bb398c97446482d057dad`，MIT。

这些实现共同表明：SPU 设备可通过 IOKit HID 枚举，但唤醒驱动、打开设备和持续回调在部分系统上可能需要更高权限。首版只做普通权限路径和安全失败，不调用 `sudo`。

## 复用决策

- 允许：基于 MIT/Apache-2.0 项目移植必要的最小代码，保留版权、许可证和 NOTICE。
- 谨慎：OpenMultitouchSupport 的预编译 XCFramework 在正式集成前需校验发布来源、checksum、Sandbox 和签名影响。
- 禁止：从无许可证仓库复制代码、UI 资源或文案。
- 不做：反编译或提取 Task Manager TMOG 的实现。只把用户可见交互作为一般性竞品观察。
