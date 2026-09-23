# Linux 以太网 PHY 与 Wi-Fi 调试

这篇专题围绕板级网络 bring-up：从设备树与 MAC/PHY 连接关系出发，逐层确认链路、协议栈和用户态。RGMII、SGMII 是 MAC 与 PHY/PCS 之间的接口模式，不等于网线侧的以太网介质；接口时序、时钟、复位和对端配置必须一起核对。

> **平台与源码基线：** Rockchip RK3588，官方 [`rockchip-linux/kernel`](https://github.com/rockchip-linux/kernel/tree/develop-6.1) 的 `develop-6.1` 分支；本文核对的代码快照为 `77168c8d5ab82399f65a80e9f807b50ba37cf483`。这是滚动分支，复现时记录实际 kernel commit、板级 DTS 和 `.config`；PHY、交换芯片、Wi-Fi 模组与接口能力以具体板卡为准。

## RK3588 + Rockchip 6.1 代码入口

- 从 [`rk3588.dtsi`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588.dtsi) / [`rk3588s.dtsi`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588s.dtsi) 追到目标板 DTS 中启用的 GMAC 节点，再核对 `compatible`、`phy-mode`、MDIO、PHY 地址、时钟、复位、pinctrl 和延迟配置。SoC 的 DTSI 只给出公共描述，不能代替板级连接信息。
- RK3588 GMAC 的 DTS compatible 包含 `rockchip,rk3588-gmac` 与 Synopsys DWMAC compatible；不要仅凭文件名假设它会匹配某个通用 Rockchip glue 驱动。沿此分支的 `of_match_table`、probe 路径和最终 MAC/PCS 驱动确认实际绑定，再判断 RGMII/SGMII 是否由该板硬件支持。
- 分支中存在 [`drivers/net/wireless/rockchip_wlan/rkwifi/`](https://github.com/rockchip-linux/kernel/tree/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/net/wireless/rockchip_wlan/rkwifi) 厂商无线驱动目录；实际驱动、固件、总线和 cfg80211/mac80211/FullMAC 路径取决于模组料号及产品配置，不能把该目录视为每块 RK3588 板的默认 Wi-Fi 实现。
- 车载 100BASE-T1/1000BASE-T1 还需要匹配的外部 PHY/交换芯片、板级接口和对端；它不是 RK3588 SoC 默认集成能力。

## 1. 先分清数据路径

有线数据大致经过：

```text
SoC MAC ↔ MAC-PHY 接口（RGMII / SGMII 等）↔ PHY ↔ 磁性器件/连接器/线缆 ↔ 对端
                    MDIO 管理总线 ────────┘
```

MAC 负责帧收发、DMA 和网络接口；PHY 负责物理层及链路协商，MDIO 用于读写管理寄存器。Linux phylib/phylink 把 PHY 状态和 MAC 驱动衔接起来。Wi-Fi 则通常是 PCIe、SDIO、USB 或平台总线上的无线设备，Linux 驱动通过 cfg80211/nl80211 与用户态连接管理工具协作。

## 2. RGMII 与 SGMII：重点看接口两端

| 项目 | RGMII | SGMII |
| --- | --- | --- |
| 连接形态 | 多根并行数据线与源同步时钟 | 单 lane SerDes 串行链路 |
| 板级敏感点 | 走线、采样窗口、TX/RX 时钟延迟 | SerDes/PCS 配置、参考时钟、极性、协商模式 |
| 常见软件信息 | MAC/PHY 两端的接口模式与延迟配置 | MAC/PHY 两端是否都按 SGMII 配置，PCS 状态是否一致 |

RGMII 的 `rgmii`、`rgmii-id`、`rgmii-rxid`、`rgmii-txid` 描述的是从 PHY 视角由谁提供接收/发送时钟延迟。不要看到链路不稳就随意切换 `*-id`：先查原理图、芯片手册、PCB 走线和 PHY 驱动配置，确认延迟不会由 PHY、MAC 和 PCB 重复加入或完全遗漏。SGMII 与 1000BASE-X 也不能只因线速相同就混用；两端控制字/PCS 语义不匹配时，可能出现链路显示正常但双工或速率信息错误。

## 3. Linux 上板排查顺序

先保存启动日志、设备树和接口状态，再从低层向高层定位：

```sh
dmesg | grep -Ei 'eth|mdio|phy|link|firmware'
ip -details link show
ethtool eth0
ethtool -S eth0
readlink /sys/class/net/eth0/phydev 2>/dev/null
```

1. 硬件：电源、复位时序、参考时钟、strap 管脚、MDIO/MDC 电平；用示波器/逻辑分析仪核对，不要只看驱动 probe 成功。
2. 枚举：设备树 `compatible`、`reg`（PHY 地址）、`phy-mode`、时钟/复位 GPIO、中断极性是否与原理图一致；确认 MDIO 能读到预期 PHY ID。
3. MAC-PHY 链路：查看接口模式、PCS/SerDes 状态、自动协商及双方速率/双工；RGMII 需要结合时序裕量与温压条件验证。
4. 网络层：链路 up 后再查 IP、ARP、路由、VLAN、防火墙和 DHCP；用持续 ping 与吞吐/丢包测试区分物理链路问题和网络配置问题。

不要先用强制速率掩盖协商错误，也不要用 `ethtool -s` 固定参数后就认定问题已修复。修改前后都记录寄存器/驱动日志、温度、线缆、对端端口和测试负载。

## 4. Wi-Fi 驱动从枚举到联网

常见分层是：总线与电源/时钟 → 芯片驱动与固件 → cfg80211（统一配置 API）→ mac80211（仅 SoftMAC 设备使用）或 FullMAC 驱动 → nl80211 → `iw`、wpa_supplicant/NetworkManager → DHCP/IP。不是所有 Wi-Fi 芯片都走 mac80211；FullMAC 通常由固件承担更多 802.11 MAC 工作。Regulatory domain 还会限制可用信道和发射行为。

```sh
dmesg | grep -Ei 'wlan|wifi|firmware|cfg80211|mac80211'
rfkill list
iw phy
iw dev
iw dev wlan0 link
iw dev wlan0 scan
ip link show wlan0
```

- 没有无线接口：先确认 SDIO/PCIe/USB 枚举、供电与复位、内核配置、模块依赖和固件加载错误。
- 能扫描但无法关联：检查频段/信道、国家码、加密套件、AP 日志、认证流程和信号质量。
- 已关联但不能上网：区分 DHCP、网关/DNS、路由和防火墙问题；`iw ... link` 已关联不代表 IP 已配置。
- 间歇掉线或吞吐差：同时收集 RSSI、重传/丢包、漫游、节能、共存干扰、天线与射频环境数据，固定测试位置和对端。

## 5. 车载以太网：在通用 PHY bring-up 上增加约束

车载以太网不是“把普通以太网 PHY 配成 100M/1G”就完成。先识别具体物理层（例如 100BASE-T1 或 1000BASE-T1）、PHY/交换芯片、MAC/PCS、主从角色、线束/连接器与对端配置，再依器件数据手册及项目适用的 IEEE / OPEN Alliance 规范执行链路、互操作、线束和 EMC 验证。Linux 侧重点仍是设备树、MDIO、phylib/phylink、PCS、时间同步需求与可观测性；合规测试不能由 `ping` 或吞吐测试替代。

## 6. 实战记录模板

每次 bring-up 至少记录：板卡/原理图版本、SoC 与 PHY/Wi-Fi 芯片料号、内核与设备树提交、PHY 地址/接口模式、供电/时钟/复位、固件版本、对端配置、复现条件、日志与测试结果。结论要写出“观测到什么、排除什么、改了什么、如何回退”，不要只留一句“网络已通”。

## 官方源码参考（Rockchip Linux 6.1）

- [Rockchip kernel `develop-6.1` 分支](https://github.com/rockchip-linux/kernel/tree/develop-6.1)
- [RK3588 公共设备树](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588.dtsi) · [RK3588S 设备树](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588s.dtsi)
- [DWMAC Rockchip glue source](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/net/ethernet/stmicro/stmmac/dwmac-rk.c)（需按 compatible 确认目标板实际绑定）
- [Rockchip WLAN driver directory](https://github.com/rockchip-linux/kernel/tree/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/net/wireless/rockchip_wlan/rkwifi)
