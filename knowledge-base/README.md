# 知识库

这是一套面向嵌入式 Linux 开发的可检索知识库，覆盖 Git/Yocto 工作流、板级网络/音频/存储 bring-up，以及内核内存和崩溃定位。

硬件与驱动专题统一以 Rockchip RK3588、[`rockchip-linux/kernel` `develop-6.1` 分支](https://github.com/rockchip-linux/kernel/tree/develop-6.1) 为源码基线。具体器件、设备树、内核配置与可用功能仍以目标板为准；专题中链接的源码快照为 `77168c8d5ab82399f65a80e9f807b50ba37cf483`。

## 内容入口

| 专题 | 解决的问题 | 线上页面 |
| --- | --- | --- |
| Git | 如何保存变更、协作、回滚和发布 | [Git 知识库](git/) |
| Yocto | 如何组织层、配方、镜像和调试流程 | [Yocto 使用知识库](yocto/) |
| 以太网 PHY 与 Wi-Fi | RGMII/SGMII、无线驱动分层与车载以太网调试 | [网络专题](ethernet-wifi/) |
| ALSA、ASoC 与 CODEC | PCM/I2S 链路、DAPM、音质、POP 与 AEC | [音频专题](audio/) |
| eMMC、MTD 与文件系统 | 块设备/原始闪存差异及 ext4、F2FS、UBI/UBIFS | [存储专题](storage/) |
| 内核内存与崩溃分析 | 内存/DMA 生命周期、panic 留证与低速总线调试 | [内核调试专题](kernel-debug/) |

从零构建系列：[Buildroot 2025.02.18](../posts/buildroot-from-zero/) · [Yocto 6.0.2](../posts/yocto-from-zero/)。

## 推荐记录格式

1. **背景**：目标、平台、版本和已知约束。
2. **操作**：可以复制执行的命令或配置片段。
3. **验证**：如何判断操作成功，给出日志、产物或测试命令。
4. **风险**：可能破坏什么、如何回滚、哪些内容依赖版本。
5. **参考**：官方文档、提交记录和关联问题。

## 知识流转

```text
采集问题 → 提炼最小复现 → 记录操作与验证 → 关联 Git 提交 → 发布到站点
```

Git 负责追踪知识和代码的演进；Yocto 负责把经过验证的配置、层和配方变成可复现的系统镜像。两者结合时，建议让每条硬件或发行版变更都对应一个清晰的提交，并记录构建分支、机器配置和镜像目标。
