# eMMC、MTD 与嵌入式 Linux 文件系统

本专题厘清三类常被混在一起的对象：eMMC 是带控制器与闪存管理功能的块设备；MTD 面向 NAND/NOR 等原始闪存；ext4、F2FS、UBIFS 处于不同的存储接口之上。选型和调试要先判断底层设备暴露的是块语义还是原始闪存语义。

> **平台与源码基线：** Rockchip RK3588，官方 [`rockchip-linux/kernel`](https://github.com/rockchip-linux/kernel/tree/develop-6.1) 的 `develop-6.1` 分支；本文核对的代码快照为 `77168c8d5ab82399f65a80e9f807b50ba37cf483`。eMMC 型号、总线模式、分区表及是否存在 SPI/raw flash 均由具体板卡和产品配置决定。

## RK3588 + Rockchip 6.1 代码入口

- RK3588S 公共 DTSI 中的 eMMC host 节点 compatible 为 `rockchip,rk3588-dwcmshc` / `rockchip,dwcmshc-sdhci`；从 [`rk3588s.dtsi`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588s.dtsi) 继续追到目标板 DTS 的 status、pinctrl、bus-width、max-frequency、供电与时序配置。对应 host 实现应先查 [`sdhci-of-dwcmshc.c`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/mmc/host/sdhci-of-dwcmshc.c)，而不是默认套用同仓库其他 Rockchip MMC host glue。
- MMC 协议与卡初始化路径从 [`drivers/mmc/core/mmc.c`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/mmc/core/mmc.c) 和 [`mmc_ops.c`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/mmc/core/mmc_ops.c) 追踪，再结合目标 eMMC 数据手册、日志与实测波形。
- RK3588S DTSI 还描述了 Serial Flash Controller；只有板上实际连接并启用匹配的 SPI NOR/SPI NAND 等器件时，才进入 [`spi-rockchip-sfc.c`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/spi/spi-rockchip-sfc.c) 与 MTD/UBI/UBIFS 路径。不能据此推断所有 RK3588 板都带 raw NAND，也不要把 eMMC 当作 MTD。

## 1. 先区分两条存储栈

```text
eMMC：SoC MMC host → MMC core/block → /dev/mmcblkN → 分区 → ext4 / F2FS
Raw NAND：NAND controller → MTD (/dev/mtdN) → UBI volume (/dev/ubiN_M) → UBIFS
```

eMMC 内部有控制器/FTL，Linux 通常把 user area 暴露为块设备；可能还有 boot partition、RPMB 等特殊区域，访问策略不同。不要把 eMMC 当 MTD 使用。Raw NAND 具有擦除块、坏块和擦写寿命等特性，不能简单套用块设备的原地覆写假设；MTD 提供原始闪存接口，UBI 再提供卷管理与磨损均衡，UBIFS 工作在 UBI volume 上。

MTD 把芯片/控制器差异抽象成可查询的容量、擦除块、写入粒度和读写/擦除操作，并可暴露 OOB/ECC 相关能力；具体 ECC 位置、强度与坏块策略仍取决于控制器和板级配置。NAND 先按擦除块擦除，再写入页；坏块管理、ECC 与 OOB 布局必须和生产烧录工具使用同一约定。`/dev/mtdN`、MTD 分区、`mtdblock` 和 UBI volume 是不同层，看到一个设备节点不代表可以安全地用通用块设备方式格式化。

## 2. eMMC bring-up 与读诊断

先检查供电、上电时序、总线宽度、CMD/CLK/DAT 信号完整性、复位脚、设备树 pinctrl/总线频率，再核对主控日志和块设备：

```sh
dmesg | grep -Ei 'mmc|sdhci|mmcblk|timeout|crc|tuning'
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
cat /sys/kernel/debug/mmc*/ios 2>/dev/null
mmc extcsd read /dev/mmcblk0
```

`mmc extcsd read` 用于读取并解码 EXT_CSD；先确认设备节点是目标 eMMC。关注初始化/枚举失败、CRC/timeout、模式切换与 tuning、重试、温度/电压条件、启动分区配置以及掉电恢复。HS200/HS400 等高速模式问题要回到主控与器件能力、布线、采样相位/tuning 和电气测量，不要只通过降频掩盖时序边缘问题。

协议分析时把它看作 CMD/响应、DAT 数据传输与忙状态组成的事务：主机上电初始化并协商工作电压/能力，读取卡身份信息并选择卡，查询 EXT_CSD，再按双方支持的总线宽度和时序切换到目标工作模式；读写还要检查数据 CRC、响应状态与写忙完成。具体阶段和高速 tuning 序列随规范版本、器件能力及 host 实现而异，应以对应 eMMC 规范、器件手册和内核 MMC host 日志为准，不能把某块板子的波形参数当成通用值。

`mmc-utils` 还支持写保护、缓存、分区属性、sanitize、RPMB 等操作，其中不少会改变设备状态或不可逆。生产介质上不要照抄写命令；先读工具说明、器件手册和项目恢复方案，并在可丢弃的测试设备上验证。

## 3. ext4、F2FS 与 UBIFS 的边界

| 文件系统 | 底层接口 | 关键思路 | 常见适用情形 |
| --- | --- | --- | --- |
| ext4 | 块设备 | block group、extent、日志等机制；日志有助于崩溃后恢复元数据一致性 | eMMC/SSD 等通用块存储，生态成熟 |
| F2FS | 块设备 | 面向闪存类块设备的 log-structured 设计，含 checkpoint 与段清理 | 需要评估写入形态、性能、恢复与工具支持的场景 |
| UBIFS | UBI volume（MTD 上层） | 面向原始闪存；通过 UBI 抽象坏块与磨损管理，文件系统维护索引/日志 | NAND 等 MTD 原始闪存 |

F2FS 不会绕过 eMMC 内部 FTL；它是在块设备之上的文件系统，底层闪存管理仍由 eMMC 控制器负责。UBIFS 不能直接挂载到普通 eMMC 分区。对于 NAND，常见关系为 MTD → UBI → UBIFS；裸 MTD 与 UBI volume 的工具及格式化流程不可混淆。

## 4. 文件系统问题的分层排查

先读而不写，采集设备、分区、挂载和内核错误信息：

```sh
findmnt
blkid
dmesg | grep -Ei 'mmc|I/O error|ext4|f2fs|ubi|ubifs|mtd'
cat /proc/mtd
ubinfo -a
mtdinfo
```

1. 若设备消失或 I/O timeout，先定位供电、控制器、信号、电源管理和介质状态；文件系统错误可能只是下层故障的结果。
2. 若块设备正常但挂载失败，确认分区/文件系统类型、内核配置、镜像与工具版本、日志中的超级块/特性不兼容信息。
3. 若 Raw NAND/UBI attach 失败，核实 MTD 分区边界、擦除块尺寸、ECC/OOB 配置、坏块和 UBI 参数；参数需与板级控制器及烧录镜像一致。
4. 只有先备份并确认目标介质后，才在离线维护窗口评估文件系统检查或修复。不要对已挂载的根文件系统运行格式化、擦除或修复工具。

## 5. 可靠性验证与案例

做一轮掉电/重启验证时，使用专用测试板和可恢复镜像：记录写入负载、剩余空间、同步策略、掉电点、启动时间、文件校验和、I/O 错误、坏块/磨损指标。覆盖大量小文件、顺序写、空间接近满、反复重启及温度变化。先在虚拟设备/测试分区复现，再推进到实际介质；任何破坏性测试都要明确数据损失范围和恢复步骤。

典型案例：系统偶发只读挂载。不要马上 `fsck` 或重刷镜像；先保存串口日志，确认 ext4/F2FS 报错前是否有 eMMC timeout/CRC，检查电源跌落、reset、缓存 flush 和写入压力，离线复制数据后再检查介质与文件系统。若底层 I/O 出错，换文件系统未必能解决根因。

## 官方源码与文档（Rockchip Linux 6.1）

- [Rockchip kernel `develop-6.1` 分支](https://github.com/rockchip-linux/kernel/tree/develop-6.1)
- [RK3588S 设备树](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588s.dtsi)
- [DWCMSHC host 驱动](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/mmc/host/sdhci-of-dwcmshc.c) · [MMC core](https://github.com/rockchip-linux/kernel/tree/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/mmc/core)
- [Rockchip SFC 驱动](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/spi/spi-rockchip-sfc.c) · [MTD/UBI 源码](https://github.com/rockchip-linux/kernel/tree/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/mtd)
- [同分支 MMC 文档](https://github.com/rockchip-linux/kernel/tree/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/driver-api/mmc) · [UBIFS 文档](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/filesystems/ubifs.rst)
