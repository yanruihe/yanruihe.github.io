# Linux 内核内存管理与崩溃分析

这条专题的目标不是背 API，而是建立从“症状和现场证据”到“对象生命周期、并发、内存来源和硬件事务”的根因分析路径。驱动 panic 经常是更早发生的越界、释放后使用、DMA 地址错误或竞态在稍后暴露。

> **平台与源码基线：** Rockchip RK3588，官方 [`rockchip-linux/kernel`](https://github.com/rockchip-linux/kernel/tree/develop-6.1) 的 `develop-6.1` 分支；本文核对的代码快照为 `77168c8d5ab82399f65a80e9f807b50ba37cf483`。分析必须使用与现场镜像完全匹配的源码提交、`.config`、DTS、`vmlinux` 和模块符号；内存保留区、CMA、IOMMU、外设 DMA 能力及检测器选项由具体板级配置决定。

## RK3588 + Rockchip 6.1 调试基线

- 从对应板卡 DTS 和 `.config` 入手确认 `reserved-memory`、CMA、IOMMU/DMA mask、console、pstore/ramoops 或 kdump 的实际配置；不要把某个 RK3588 开发板的内存布局套到其他板卡。
- Oops/vmcore 符号化时使用产生该镜像的精确 `develop-6.1` commit、未剥离 `vmlinux`、模块、`System.map` 与 build ID。分支名相同并不代表构建产物可互换。
- KASAN、KFENCE、KCSAN、lockdep 和 kdump 等支持受该分支代码、内核配置、启动链与可用内存共同约束；先在对应 RK3588 测试镜像验证开销与可用性，再决定产品配置。

## 1. 驱动中常见的内存与生命周期

- **页分配器 / slab**：大块页、常见小对象缓存分别服务不同粒度；`kmalloc`、`kzalloc` 常用于物理连续的小块内核对象，`vmalloc` 提供虚拟连续但物理页可不连续的区域。DMA 场景不能把“CPU 有虚拟地址”当成设备可用 DMA 地址。
- **DMA API**：按设备 DMA mask 与映射方向获取 DMA 地址；区分 coherent 与 streaming 映射，遵守 map/unmap/sync 生命周期。不要把 `virt_to_phys()` 当作通用 DMA 映射办法。
- **分配上下文**：`GFP_KERNEL` 可能睡眠；中断/原子上下文不能使用可能阻塞的分配方式。检查锁持有状态、调用上下文和失败回滚路径。
- **对象所有权**：引用计数、completion、workqueue、timer、IRQ、DMA 回调都可能延长对象生命周期。remove/error path 必须停止新请求、同步异步执行者、释放 IRQ/DMA，再释放对象。
- **并发与锁**：明确哪些字段由谁保护、锁顺序和 IRQ 上下文规则。只给指针加锁，不等于异步回调退出后对象仍有效。

读代码时画出资源取得/释放配对表：`alloc ↔ free`、`map ↔ unmap`、`request_irq ↔ free_irq`、`submit ↔ complete/cancel`。对每个错误出口、probe defer、remove、suspend/resume 都追一次状态机。

## 2. 崩溃现场先保全，再解释

稳定复现前，先确认设备有可用的串口/控制台日志和准确匹配的符号文件。发布包应保存内核配置、源码提交、未剥离 `vmlinux`、`System.map`、模块符号及 build ID；只有版本完全匹配时，地址和行号才可信。启用 pstore/ramoops 或 kdump 时，要验证启动链、保留内存和存储路径，不能只看配置项“已打开”。

```text
现场：完整 Oops/Panic、时间、负载、温度、触发操作、外设状态
制品：精确匹配的 vmlinux、模块、System.map、.config、源码提交/build ID
分析：异常类型 → PC/LR/寄存器 → 调用栈 → 首个可疑驱动帧 → 对象生命周期/并发/DMA
验证：最小复现 → 加诊断/检测器 → 修复 → 原场景与回归压力测试
```

看到 `BUG: unable to handle...`、`Oops` 或 `panic` 后，先区分 NULL/非法地址、权限错误、栈/越界、锁死和硬件异常。读取 fault address、访问方向、PC/LR、寄存器与完整调用栈，关联反汇编和对应源码；再判断栈顶是否只是受害位置，向前追踪指针来源、最后一次写入、异步回调和设备时序。

如果有 vmcore，可用与崩溃内核完全匹配的 `vmlinux` 配合 `crash` 检查任务、栈、模块和内存；若仅有串口日志，也要保留原始完整内容，不能只截最后几行。没有可信证据时，结论标记为假设，并设计能证伪它的实验。

## 3. 检测器与诊断配置

在可承受开销的开发/测试内核中，按问题选择工具：KASAN 查越界和 use-after-free；KFENCE 以较低开销抽样检测内存错误；KCSAN 发现部分数据竞争；lockdep 查锁依赖问题；kmemleak 辅助发现可能泄漏；UBSAN 捕获部分未定义行为。它们会改变时序和资源占用，偶发竞态可能因此改变表现；要同时有未插桩基线与检测器构建。

持续运行的产品还应设计崩溃留证：串口/网络控制台、pstore/ramoops、持久日志或 kdump vmcore。容量、保留内存、写入寿命、隐私敏感信息和复位策略都要评估。不要为了更容易复现就在用户设备上随意启用自动 panic 或主动触发崩溃。

## 4. 低速总线：软件日志配合电气证据

### I2C

检查地址/7-bit 与 10-bit 约定、START/STOP、重复 START、ACK/NACK、上拉、上升沿、总线频率、仲裁/时钟拉伸和器件上电时序。Linux 侧区分 adapter/controller 错误、传输 errno 和芯片寄存器返回值。`i2cdetect` 会对地址发探测事务，某些设备不适合被探测；先查原理图和芯片手册，避免在活动总线上盲扫。

### SPI

核对 CPOL/CPHA、片选有效极性、字长、最高频率、收发方向和事务边界。逻辑分析仪同时看 CS/SCLK/MOSI/MISO；只看到控制器 transfer 返回成功，不代表设备采样边沿、寄存器地址或延迟满足器件时序。

### UART

核对波特率、数据位/校验/停止位、TTL 电平与 RS-232/RS-485 收发器差异、TX/RX 交叉、流控和中断/FIFO 溢出。串口乱码先用已知配置的 USB-UART 与示波器/逻辑分析仪判断位宽和电平，再查驱动时钟与 pinmux；日志本身也可能因 FIFO overrun 丢字节。

## 5. 分析演练：偶发 I2C 驱动 panic

1. 固定板卡、固件、总线速率、负载、温度和触发频率，先确认崩溃是否总在同一访问位置。
2. 保留完整 panic 与 build artifacts，用 `addr2line`/`crash` 映射准确符号；检查故障地址是否来自被释放设备对象或空的传输缓冲区。
3. 追踪 probe、IRQ、workqueue、remove 和错误清理路径；核对是否在取消 work/timer/IRQ 完成前释放状态对象，或是否在锁/原子上下文里睡眠。
4. 用 KASAN/KFENCE/lockdep 以及总线波形分别检验内存生命周期、锁顺序和器件时序假设；一次只改变一个变量。
5. 修复后覆盖 probe 失败、热拔插（若硬件支持）、反复 suspend/resume、总线错误注入和长时间压力，并确认无新泄漏/告警。

## 6. 复盘模板

保存：症状与复现率、崩溃原始日志、硬件/软件版本、匹配符号制品、可疑对象生命周期图、排除过的假设、检测器和测量结果、根因证据、修复 diff、回归测试与剩余风险。把“发生了什么”与“为什么发生”分开写，后者必须由证据支持。

## 官方源码与文档（Rockchip Linux 6.1）

- [Rockchip kernel `develop-6.1` 分支](https://github.com/rockchip-linux/kernel/tree/develop-6.1)
- [RK3588 公共设备树](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588.dtsi) · [RK3588S 设备树](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588s.dtsi)
- [同分支 kdump 文档](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/admin-guide/kdump/kdump.rst) · [KASAN](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/dev-tools/kasan.rst) · [KFENCE](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/dev-tools/kfence.rst)
- [I2C 驱动文档](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/driver-api/i2c.rst) · [SPI 驱动文档](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/driver-api/spi.rst) · [串口驱动文档](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/driver-api/serial/driver.rst)
