# Linux 音频驱动：ALSA、ASoC 与 CODEC

本文从“数字音频为什么无声、失真、爆音”出发，建立可执行的排查路径。嵌入式音频不是只把 CODEC 驱动 probe 成功：CPU DAI、CODEC DAI、机器连接、时钟、DMA、DAPM 路径、模拟供电和用户态参数必须同时成立。

> **平台与源码基线：** Rockchip RK3588，官方 [`rockchip-linux/kernel`](https://github.com/rockchip-linux/kernel/tree/develop-6.1) 的 `develop-6.1` 分支；本文核对的代码快照为 `77168c8d5ab82399f65a80e9f807b50ba37cf483`。板级声卡、外置 CODEC/功放、时钟主从与路由以目标板 DTS、原理图和 `.config` 为准。

## RK3588 + Rockchip 6.1 代码入口

- [`rk3588.dtsi`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588.dtsi) 定义了如 `rockchip,rk3588-i2s-tdm` 的 I2S/TDM 控制器节点；在板级 DTS 中继续追踪被启用的控制器、pinctrl、时钟、DMA 和声卡 link。
- CPU DAI 驱动入口是 [`sound/soc/rockchip/rockchip_i2s_tdm.c`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/sound/soc/rockchip/rockchip_i2s_tdm.c)。目标 CODEC、功放、声卡 machine/link、DAI 格式及 MCLK/BCLK/LRCLK 角色由具体板卡决定；不要把某一开发板的音频路由当作 RK3588 固定配置。
- AEC、回声路径和音质算法通常属于产品音频 DSP/HAL/用户态实现，不能仅凭 SoC I2S 驱动推定其已提供。

## 1. 播放链路与 ASoC 组件

```text
应用/aplay → ALSA PCM → DMA/platform → CPU DAI (I2S/PCM) ⇄ CODEC DAI → DAC/模拟输出/功放
                                      Machine driver 描述板级连接与时钟/控制
```

- **ALSA PCM**：承接采样格式、采样率、声道、period/buffer 与播放/录音数据流。
- **CPU DAI**：SoC 侧 I2S/PCM 接口和时钟/数据格式控制。
- **CODEC DAI/驱动**：CODEC 的数字接口、寄存器控制、DAC/ADC、混音器和 DAPM 描述。
- **Machine driver**：把 SoC、CODEC、板级功放/耳机检测等连接成声卡，并描述时钟与板级策略。
- **DMA/platform**：搬运 PCM 数据；周期中断、FIFO 水位或总线带宽异常会造成 underrun/overrun。

ASoC 的 DAPM 根据活动流和音频路由启停电源部件。Mixer 控件是否存在、路由图是否连通、widget 是否上电，都会决定声卡“看起来正常”但端点无声的现象。

## 2. 首次 bring-up：从枚举到实际出声

```sh
dmesg | grep -Ei 'asoc|alsa|snd|codec|i2s|dma'
cat /proc/asound/cards
aplay -l
arecord -l
amixer -c 0 contents
```

确认内核配置、设备树的 sound card/link、I2S 控制器和 CODEC 地址/电源/reset、DAI 格式、主从时钟关系与采样率约束。再核对板级线路：扬声器功放使能脚、耳机插入检测、模拟电源、麦克风偏置和 mute GPIO。

用 `speaker-test` 或 `aplay` 播放已知 PCM/WAV 测试信号；先选择声卡和 ALSA 控件，不要把测试文件格式不支持误判为驱动故障：

```sh
aplay -D hw:0,0 -f S16_LE -r 48000 -c 2 test.wav
arecord -D hw:0,0 -f S16_LE -r 48000 -c 2 -d 5 capture.wav
```

先确认硬件实际支持的格式和时钟。示例参数仅是常见测试配置，不代表所有板卡都支持 48 kHz、16-bit、双声道。

## 3. 无声、失真与 XRUN 的定位

| 现象 | 优先检查 |
| --- | --- |
| 找不到声卡/PCM | 驱动 probe、设备树 phandle、I2C/SPI CODEC 枚举、组件 defer probe、内核配置 |
| PCM 能启动但无声 | `amixer` mute/音量、DAPM route、功放使能、模拟电源、DAC 路由、耳机/扬声器选择 |
| 噪声、变调或失真 | MCLK/BCLK/LRCLK、主从关系、极性/slot/位宽、采样格式、左右声道映射、地线/模拟电源 |
| `underrun` / `overrun` | DMA 配置与地址、period/buffer、IRQ 延迟、CPU 负载、总线带宽、音频路由格式 |
| 录音全零 | 麦克风 bias、输入 mux、ADC 电源、增益、时钟、物理输入和 `arecord` 参数 |

示波器可直接观察 MCLK、BCLK、LRCLK 和串行数据；用逻辑分析仪核对协议时，采样时钟/位宽需足够。把软件控制值、波形、录音文件和听感关联起来，避免只凭耳朵猜寄存器。

## 4. POP/CLICK 与音质调优

爆音往往来自电源/偏置/模拟输出与数字静音的时序不协调，而不是单纯“把音量调小”。逐项验证：播放前 mute → 上电并稳定电源/参考时钟 → 配置 CODEC 与路由 → 按芯片建议等待偏置稳定 → 打开 DAC/功放并渐进解除 mute；停止时按相反顺序静音、关闭功放和电源。具体时序、延时、放电路径必须服从 CODEC/功放数据手册。ASoC 提供 DAPM 和 pop/click 管理机制，但板级电路与驱动实现仍决定效果。

优化音质要固定设备、声源、输出负载和测量条件，再调整数字增益、模拟增益、滤波器、EQ、采样格式和动态处理。保留原始录音/回放，比较频响、底噪、THD+N、削波和延迟；未经测量不宜把主观听感作为唯一结论。

## 5. 回音消除：先确认系统架构

AEC（Acoustic Echo Cancellation）需要麦克风近端信号和扬声器播放参考信号，并依赖稳定的时戳、采样率、双工路由与延迟模型。它常由 DSP、音频 HAL 或用户态音频处理链实现，并非 CODEC 上一个通用开关就能解决。调试时记录播放参考与麦克风采样的时间对齐、设备/声学路径延迟、双讲场景、回声尾长和残余回声；先确认参考信号确实送到 AEC、录音路径确实经过 AEC，再评估算法参数和声学结构。

## 6. 验证清单

每次改动记录内核/设备树、CODEC 与功放版本、控件状态、DAI 格式/时钟、PCM 参数、波形、录音/回放样本及测试负载。覆盖冷启动、快速启停、耳机插拔、音量变化、休眠恢复、播放录音并发和高负载；分别验证功能、爆音、噪声、失真与延迟。

## 官方源码与文档（Rockchip Linux 6.1）

- [Rockchip kernel `develop-6.1` 分支](https://github.com/rockchip-linux/kernel/tree/develop-6.1)
- [RK3588 公共设备树](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588.dtsi)
- [Rockchip I2S/TDM 驱动](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/sound/soc/rockchip/rockchip_i2s_tdm.c) · [同分支 ASoC 文档](https://github.com/rockchip-linux/kernel/tree/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/sound/soc) · [CODEC 驱动目录](https://github.com/rockchip-linux/kernel/tree/77168c8d5ab82399f65a80e9f807b50ba37cf483/sound/soc/codecs)
