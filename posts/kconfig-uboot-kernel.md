# U-Boot 与 Linux 内核 Kconfig 核心机制：从选项到编译结果

U-Boot 和 Linux 内核都用 Kconfig 描述可选功能、平台约束与依赖关系。读懂 Kconfig 的关键，不是记住菜单路径，而是能追出一个符号从定义、可见性和值解析，到 `.config`、生成头文件和最终对象文件的完整过程。本文用 RK3588 的 Rockchip U-Boot 与 Linux 6.1 源码举例。

> **源码基线：** Linux 使用 [`rockchip-linux/kernel`](https://github.com/rockchip-linux/kernel) 当前默认分支 `develop-6.1`，核对快照为 `77168c8d5ab82399f65a80e9f807b50ba37cf483`；U-Boot 使用 [`rockchip-linux/u-boot`](https://github.com/rockchip-linux/u-boot) 当前默认分支 `next-dev`，核对快照为 `1c535d65b8509f388d09e49fb6961f49fda35a1d`。两条分支都可能继续移动，复现或发布时记录实际 commit。

## 1. 一次配置如何进入固件

```text
Kconfig 文件定义符号、类型、依赖、默认值和菜单结构
        ↓
defconfig 提供产品/开发板的起始选择
        ↓  menuconfig / olddefconfig / savedefconfig
.config 保存最终选择
        ↓  Kconfig 生成配置头文件和 Make 可读配置
Makefile 按 CONFIG_* 选择目录、对象和编译规则
        ↓
U-Boot / Image / modules 等构建产物
```

Kconfig 本身不编译 C 文件，也不决定设备运行时是否已连线。它计算“这次构建允许哪些功能”，再把结果交给 Kbuild、U-Boot 的 Makefile 和 C 预处理器。源码中搜到一个 `CONFIG_*` 名字，并不代表它一定在当前 `.config` 中为 `y`；反过来，写入 `.config` 也不能绕过 Kconfig 的依赖约束。

## 2. 配置符号的类型和值

| 类型 | 常见用途 | 可选值/示例 |
| --- | --- | --- |
| `bool` | 只能启用或关闭的功能 | `y` / `n` |
| `tristate` | 内核可内建、编模块或关闭的驱动 | `y` / `m` / `n` |
| `string` | 路径、名称、字符串参数 | `"ttyS0"` |
| `int`、`hex` | 数值、地址或掩码 | `115200`、`0x...` |

内核 `tristate` 的 `y` 表示编入内核，`m` 表示生成模块，`n` 表示不构建；只有模块支持及上层依赖允许时，`m` 才可选。对应 C 宏也不同：内建一般是 `CONFIG_FOO`，模块通常是 `CONFIG_FOO_MODULE`。在 C 代码里根据需要用内核提供的 `IS_ENABLED()` / `IS_REACHABLE()`，不要假设 `#ifdef CONFIG_FOO` 对 `m` 与 `y` 等价。

Linux 内核广泛使用 `tristate` 来区分内建和模块；U-Boot 的板级功能配置则通常围绕 `bool`、字符串和数值选项，最终链接进 U-Boot 镜像，不应把 Linux 的 `=m` 模块模型套用到 U-Boot。两套工程共享 Kconfig 的基本语言和配置流程，但配置符号、defconfig、生成文件与构建目标各自独立。

`choice` 用来表示互斥选项，例如选择一种实现或默认值来源。`default` 是未被用户配置覆盖时的取值建议，不等同于强制开启；`def_bool`、`def_tristate` 则把类型和默认表达式合并书写。

## 3. `depends on`：决定选项何时可见、最多能取什么值

菜单层级和依赖共同约束符号。父菜单的依赖会传递到子项；`depends on` 条件不满足时，选项可能从 `menuconfig` 中消失，已保存值也会被重新计算为允许的范围。Kconfig 采用三值逻辑，多个依赖通常相当于逻辑 AND。

Rockchip Linux 6.1 的 `sound/soc/rockchip/Kconfig` 中，I2S/TDM 驱动依赖 Rockchip ASoC 支持和时钟框架，形式类似：

```Kconfig
config SND_SOC_ROCKCHIP_I2S_TDM
	tristate "Rockchip I2S/TDM Device Driver"
	depends on HAVE_CLK && SND_SOC_ROCKCHIP
```

如果这个选项在菜单里找不到，先检查父选项 `SND_SOC`、`SND_SOC_ROCKCHIP`、`HAVE_CLK` 以及目标树里的实际 Kconfig 定义。不要先手工往 `.config` 塞入 `CONFIG_SND_SOC_ROCKCHIP_I2S_TDM=y`：下次运行配置器时，依赖不满足的值会被清除或改写。

`depends on` 还可用于限制可选值上限。例如依赖项为 `m` 时，依赖它的 tristate 子项不能设为 `y`。菜单里显示“不可选/灰色”与配置完全不存在是两种情况；按 `/` 搜符号通常能看到它的定义位置和依赖链。

## 4. `select` 与 `imply`：反向依赖要谨慎

`select FOO` 会从使用者一侧强制提高 `FOO` 的最低值，却不完整检查 `FOO` 自己的依赖。这可能制造出源码无法安全构建的组合，因此内核 Kconfig 维护指南建议只在目标符号没有额外依赖、通常为隐藏的基础能力符号时谨慎使用 `select`。

`imply FOO` 是较弱的建议：它会倾向于开启 `FOO`，但用户或直接依赖仍可把它关闭。面向硬件驱动的可见选项通常应通过 `depends on` 表达前置条件，而不是让一个驱动 `select` 另一个有复杂依赖的驱动。

```Kconfig
config DRIVER_A
	tristate "Driver A"
	depends on I2C

config DRIVER_A_HELPER
	bool
	select GENERIC_HELPER
```

这里把硬件总线需求放在可见驱动上；`select` 只用于无复杂前置条件的隐藏辅助符号。不能把这段当成任意项目都可复制的固定模式，新增符号前先检查被依赖符号的定义和约束。

## 5. `.config`、defconfig 与生成文件

- **`defconfig`**：产品或开发板的配置起点，通常只保存相对默认值的差异，便于评审和长期维护；它不一定是完整的最终 `.config`。
- **`.config`**：配置器为当前源码、架构和依赖计算出的完整结果。切换分支或 Kconfig 定义后，旧配置可能出现新选项、废弃选项或不同默认值。
- **生成配置文件**：Kconfig/Kbuild 将选项转换成 Make 可读的 `auto.conf` 等文件以及供 C 代码使用的配置头文件；它们通常由构建系统重建，不应当作为产品唯一的配置源。

U-Boot 还有兼容旧配置系统的过渡层：Kconfig 会生成配置文件，同时构建过程仍可能生成 `include/config.h`、`include/autoconf.mk` 及 SPL/TPL 的兼容文件；一些遗留宏也仍位于 `include/configs/<board>.h`。新增配置项优先在 Kconfig 中定义，不要假设 U-Boot 与 Linux 的配置文件布局完全相同。

内核常用命令：

```bash
# Rockchip Linux 6.1；起始 defconfig 之后仍须叠加具体板级配置
make ARCH=arm64 rockchip_linux_defconfig
make ARCH=arm64 menuconfig
make ARCH=arm64 olddefconfig
make ARCH=arm64 savedefconfig
```

U-Boot 使用目标板 defconfig，例如该 Rockchip U-Boot 分支包含 `rk3588_defconfig`：

```bash
make rk3588_defconfig
make menuconfig
make olddefconfig
make savedefconfig
```

不要把 `make defconfig` 当作任何板子的配置：在 U-Boot 中该快捷目标通常用于 sandbox；RK3588 应选择实际板卡/BSP 提供的目标 defconfig。保存精简配置后，应评审 defconfig 的差异，再在干净输出目录中重新生成 `.config` 验证它确实包含所需设置。

## 6. 从 `CONFIG_*` 到实际目标文件

Kconfig 选项只有被 Makefile 或 C 代码消费，才会影响产物。例如 Kbuild 常用：

```make
obj-$(CONFIG_SND_SOC_ROCKCHIP_I2S_TDM) += rockchip_i2s_tdm.o
```

`CONFIG_...=y` 时对象进入内建目标；为 `m` 时走模块构建；为 `n` 时不纳入。也可以在 C 文件中用 `#if IS_ENABLED(CONFIG_FOO)` 包裹可选实现。排查“菜单显示开了但目标文件没生成”，要顺着三处查：最终 `.config` 值、Makefile 的 `obj-*`/条件、构建日志中该目录是否被遍历。还要确认构建使用的输出目录与源码树，避免检查了 A 配置却编译 B 配置。

## 7. RK3588 案例：Kconfig 与设备树各管一段

Rockchip U-Boot 的 `configs/rk3588_defconfig` 会启用 RK3588 SoC 相关配置，例如 `CONFIG_ARCH_ROCKCHIP=y`、`CONFIG_ROCKCHIP_RK3588=y`。Linux 内核则有自己的 Kconfig 符号，例如 `CONFIG_ARCH_ROCKCHIP` 与驱动选项 `CONFIG_SND_SOC_ROCKCHIP_I2S_TDM`。两边名称都带 `CONFIG_`，但属于不同源码树、不同构建结果，不能互相替代。

对 I2S/TDM 来说，Kconfig 负责让驱动参与编译；RK3588/板级 DTS 的 compatible、status、pinctrl、时钟、DMA 和声卡连接负责描述运行时有哪些设备实例及其连接方式。驱动编进内核但 DTS 节点为 `disabled`，设备仍不会 probe；DTS 节点写了 `okay`，但驱动没编进内核，也不会出现可用驱动。定位问题时把 `.config`、实际加载的 DTB、驱动绑定日志与板卡原理图放在一起核对。

```text
Kconfig 允许构建驱动
       + 目标 .config 选择驱动为 y/m
       + DTS 描述兼容设备并启用节点
       + 板级时钟/电源/pinctrl/连线正确
       ↓
驱动 probe 才有条件成功，设备才可能工作
```

## 8. 在 Buildroot 和 Yocto 中保存内核配置

Buildroot 直接提供 `make linux-menuconfig` 和 `make linux-update-defconfig`，分别用于交互配置和回存 defconfig。保存时使用产品板级文件，而不是只留某次构建目录里的完整 `.config`。

Yocto 的 kernel recipe 通过 `defconfig` 或配置 fragments 组装最终 `.config`。在正确的 build 环境中运行对应 kernel provider 的 `menuconfig`，用 `diffconfig` 提取改动，再把最小 fragment 和 `.bbappend` 放进产品 layer；不要长期手工编辑 `tmp/work/.../.config`，因为 BitBake 的配置任务会重新生成它。切换 kernel 分支/commit 后需重新验证 fragment 是否仍被接受、选项是否仍存在。

这两篇构建文章展示了 Rockchip kernel 默认分支的具体配置入口：[Buildroot + RK3588](/posts/buildroot-from-zero/) · [Yocto + RK3588](/posts/yocto-from-zero/)。

## 9. 常见现象与排查顺序

| 现象 | 先检查 | 下一步 |
| --- | --- | --- |
| 菜单中搜不到符号 | 符号拼写、当前源码分支、父菜单及依赖 | 用 `/` 搜索，读取定义文件和完整 depends 链 |
| `.config` 中选项被改回 `n` | `depends on`、架构选择、Kconfig 新旧差异 | 重新运行 `olddefconfig`，比较修改前后并找出首个失败依赖 |
| `select` 后构建报缺失符号/类型 | 被 select 符号自身依赖、可见 prompt 和 tristate 值 | 改为正确依赖关系，避免以强制值掩盖不兼容组合 |
| 选项为 `y` 但对象没有编译 | 实际构建使用的 `.config`、Makefile 条件、是否走到该目录 | 查 `V=1` 日志和 `obj-y` / `obj-m` 条件 |
| 驱动编译了但设备不 probe | DTB 是否匹配运行板卡、compatible/status、依赖资源 | 对照启动时加载的 DTB、pinctrl/clock/reset 和 probe 日志 |
| Yocto/Buildroot 保存配置后下次消失 | 配置是否保存到受版本控制的 layer/defconfig | 由正式 build system 重新生成并复核最终配置 |

## 参考源码与文档

- [Rockchip Linux kernel 默认仓库与 `develop-6.1` 分支](https://github.com/rockchip-linux/kernel/tree/develop-6.1) · [Linux Kconfig 语言文档（同一源码快照）](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/kbuild/kconfig-language.rst)
- [Rockchip kernel `sound/soc/rockchip/Kconfig`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/sound/soc/rockchip/Kconfig) · [RK3588 kernel defconfig](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/configs/rockchip_linux_defconfig)
- [U-Boot 官方 Kconfig 文档](https://docs.u-boot.org/en/latest/develop/kconfig.html) · [Rockchip U-Boot `next-dev`](https://github.com/rockchip-linux/u-boot/tree/next-dev) · [`rk3588_defconfig`](https://github.com/rockchip-linux/u-boot/blob/1c535d65b8509f388d09e49fb6961f49fda35a1d/configs/rk3588_defconfig)
- [Buildroot 用户手册：内核配置](https://buildroot.org/downloads/manual/manual.html) · [Yocto 6.0.2 Kernel Development Manual](https://docs.yoctoproject.org/6.0.2/kernel-dev/common.html) · [Yocto Git source revision variables](https://docs.yoctoproject.org/6.0.2/ref-manual/variables.html#term-SRCREV)

相关博文：[Buildroot 从零构建](/posts/buildroot-from-zero/) · [Yocto 从零构建](/posts/yocto-from-zero/) · [RK3588 硬件与驱动知识库](/knowledge-base/)。
