# 从零构建嵌入式 Linux：Buildroot 2025.02.18

本篇选择 Buildroot 2025.02.18 LTS、`qemu_x86_64_defconfig` 和 QEMU。目标不是交叉编译某个单独程序，而是从源码生成交叉工具链、Linux 内核、根文件系统，最后启动并验证一个可运行的系统。本例用 QEMU 的 `-kernel` 直接装载内核，因此不经过 BIOS、U-Boot 等常规固件引导路径；换成真实 ARM 板时，Bootloader、设备树和板级驱动还需要对应 BSP。

## 先弄清原理：Buildroot 为什么能构建一整套系统？

Buildroot **不是用 C 语言重新实现 Linux**。它本身主要由 Makefile、Kconfig 配置、脚本和补丁组成；内核、GCC、C 库、BusyBox 等来自各自独立的上游项目。Buildroot 负责选择版本与选项、处理包之间的依赖、下载源码、交叉编译、安装到目标根文件系统，再生成指定格式的镜像。因此，`make` 触发的是一条受配置驱动的构建链，而不是编译一个巨大的 C 项目。

```text
板级 defconfig → .config → 工具链（binutils / GCC / C 库，或外部工具链）
                          → 目标软件（例如 BusyBox 和自己的应用）
                          → 内核 / 可选 Bootloader → 根文件系统 → 镜像
```

这是一张**职责图**，不是严格的任务执行顺序；具体组件取决于配置。本文的 `qemu_x86_64_defconfig` 生成内核和根文件系统，QEMU 用 `-kernel` 直接启动内核，**没有在这个示例中构建 U-Boot，也没有测试固件寻找内核的阶段**。C 库也不是固定为 musl，可按配置选择 glibc、musl 或 uClibc-ng 等。BusyBox 提供精简用户空间工具和默认 init；它不是内核，也不是 Buildroot 本身。

## 1. 准备构建主机

在 Linux 主机上以普通用户构建；Windows 用户可用 Linux 虚拟机或 WSL2 的 Linux 文件系统，不要把大型构建目录放在 Windows 挂载盘。下面以 Ubuntu 24.04 为例，其他发行版按 [Buildroot 主机依赖](https://buildroot.org/downloads/manual/manual.html#requirement-mandatory) 安装等价软件。预留足够磁盘空间、内存和网络带宽；首次下载和编译可能耗时较长。

```bash
sudo apt update
sudo apt install -y build-essential git wget cpio unzip rsync file bc \
  bzip2 gzip xz-utils patch sed gawk qemu-system-x86
```

不要用 `sudo make`。这里的 sudo 仅用于安装主机依赖。

## 2. 固定版本并生成基础配置

```bash
git clone --branch 2025.02.18 --depth 1 https://gitlab.com/buildroot.org/buildroot.git buildroot
cd buildroot
git describe --tags --always
make qemu_x86_64_defconfig
make
```

`make` 会下载源码并依次构建工具链、目标软件、内核和根文件系统。首次构建不要盲目加顶层 `-j`；构建结束后检查：

```bash
ls -lh output/images/
test -s output/images/bzImage
test -s output/images/rootfs.ext2
```

读懂产物目录，排错和发布才不会混淆：

| 路径 | 用途 |
| --- | --- |
| `.config` | 本次构建的完整选择；用 `make savedefconfig` 提炼为便于版本管理的板级配置 |
| `output/build/` | 各组件的解包、配置和编译现场 |
| `output/host/` | 主机工具、交叉工具链和目标 sysroot；`output/staging/` 是指向 sysroot 的兼容性链接 |
| `output/target/` | 接近目标根文件系统的安装树，但缺少正确设备节点和部分权限，**不能直接部署** |
| `output/images/` | 内核、根文件系统及当前配置所选择的其他最终产物 |

## 3. 用 QEMU 启动并验证

此命令对应所选 defconfig 自带的 [QEMU 说明](https://gitlab.com/buildroot.org/buildroot/-/raw/2025.02.18/board/qemu/x86_64/readme.txt)：

```bash
qemu-system-x86_64 -M pc \
  -kernel output/images/bzImage \
  -drive file=output/images/rootfs.ext2,if=virtio,format=raw \
  -append 'rootwait root=/dev/vda console=tty1 console=ttyS0' \
  -serial stdio -net nic,model=virtio -net user
```

登录提示默认出现在 QEMU 图形窗口。进入系统后执行：

```sh
uname -a
cat /proc/cmdline
cat /proc/1/comm
mount | grep ' on / '
```

看到内核版本、`root=/dev/vda`、init 进程及挂载的根文件系统，才算走通“内核 → init → 用户空间”。离开 QEMU 时从客户机执行 `poweroff`；不要直接修改 `output/images/rootfs.ext2` 充当持久配置。

## 4. 加入一个开机动作

Buildroot 的默认轻量方案使用 BusyBox init，而不是自动拥有 systemd。先运行 `mkdir -p board/demo/overlay/etc/init.d`，再创建 `board/demo/overlay/etc/init.d/S99demo`，内容为：

```sh
#!/bin/sh
case "$1" in
  start) echo 'Buildroot demo is ready' >/dev/console ;;
  stop) ;;
  *) exit 1 ;;
esac
```

设置可执行权限：

```bash
chmod +x board/demo/overlay/etc/init.d/S99demo
make menuconfig
```

在 **System configuration → Root filesystem overlay directories** 中填入 `board/demo/overlay`，保存后执行 `make` 并再次启动 QEMU。启动日志应出现 `Buildroot demo is ready`，在客户机也可运行 `test -x /etc/init.d/S99demo`。正式应用应做成 Buildroot package，并根据选定 init 系统提供启动配置；overlay 适合这个最小演示，不应代替长期的包管理。

## 5. 固化配置、适配硬件与排错

```bash
make savedefconfig BR2_DEFCONFIG=board/demo/demo_defconfig
git status --short
```

提交 `demo_defconfig`、overlay、补丁及版本清单，不提交整个 `output/`。只有配置文件还不足以保证逐字节复现：还要固定 Buildroot 与外部源码版本、补丁、工具链及构建环境。对真实板卡，先选择或编写匹配的 board defconfig，再确认 CPU/ABI、Bootloader、内核配置、设备树、存储分区、串口和刷机方式；QEMU 镜像不能直接刷入不相干的硬件。构建失败先读最后一个失败包的日志和 `output/build/`，启动失败先核对内核命令行、根设备和串口，避免无目的地清空整个输出目录。Buildroot 也不会自动解决 OTA、安全更新和产品生命周期管理；软件许可证和源代码提供义务须在发布前处理。若项目需要多层元数据和发行版策略，可对照[Yocto 从零构建篇](/posts/yocto-from-zero/)选择方案。

## 6. 从配置到镜像：逐层理解这次构建

Buildroot 的菜单不是在 Linux 源码里打开一个“全部编译”开关，而是在描述目标产品需要哪些组件。`make qemu_x86_64_defconfig` 把一组经过维护的默认选择写进 `.config`；`make menuconfig` 会在这份配置上修改选项；顶层 Makefile 再根据各软件包的依赖关系安排任务。工具链先提供目标架构的编译器、链接器和 C 库，后续用户空间程序和库都使用这套工具链；内核和 Bootloader 则分别由它们自己的上游源码构建。

例如选中一个依赖 OpenSSL 的网络程序时，Buildroot 会把 OpenSSL 纳入依赖图，先准备它需要的目标头文件和库，再交叉编译该程序。每个包的 `.mk` 文件说明源码从哪里来、怎样配置和编译、安装哪些文件；`Config.in` 决定它如何出现在配置菜单中。根文件系统 skeleton、overlay、选中的包和权限/设备表共同决定目标系统的用户空间，文件系统生成器最后把它们打包成 ext2、tar、squashfs 等所选格式。这就是一个 Makefile 驱动的集成工程能构建完整系统的原因：Buildroot 是组织者，具体组件仍是独立项目。

| 阶段 | 主要输入 | 典型结果 |
| --- | --- | --- |
| 配置 | defconfig、menuconfig、板级配置 | `.config`、内核与 BusyBox 配置 |
| 工具链 | CPU/ABI、C 库、编译器版本 | `output/host/bin/` 下的交叉工具 |
| 系统组件 | 内核、可选 Bootloader、BusyBox、应用包 | 安装到 staging/target 的文件 |
| 镜像生成 | rootfs skeleton、overlay、设备表、文件系统类型 | `output/images/` 中可启动或可烧录的文件 |

Buildroot 能选择内置工具链，也能接入外部交叉工具链；C 库可按目标选择。QEMU 示例通过 `-kernel` 直接加载内核，适合先验证内核与用户空间协作，但不会验证固件或 Bootloader 如何找到并装载内核。真实板卡通常要另外选对 Bootloader、DDR/启动介质初始化、设备树和厂商 BSP。哪些步骤由 Buildroot 管、哪些由板级厂商提供，要在开工时写清楚。

## 7. 配置修改与小步迭代

第一次构建后，建议先保存原始配置，再只改一个选项观察变化：

```bash
cp .config board/demo/qemu_x86_64_base.config
make menuconfig
diff -u board/demo/qemu_x86_64_base.config .config
make
make savedefconfig BR2_DEFCONFIG=board/demo/demo_defconfig
diff -u configs/qemu_x86_64_defconfig board/demo/demo_defconfig || true
```

在菜单中常见的调整位置包括 **Target options**（架构和 ABI）、**Toolchain**（C 库与编译器）、**System configuration**（hostname、密码策略、init 和设备管理）、**Target packages**（用户空间软件）、**Kernel** 以及 **Filesystem images**。先确定目标板和应用的需求，再选择组件；随意增加包会放大镜像、增加依赖与攻击面，也会增加后续升级责任。

Linux 内核、BusyBox 和 C 库各有自己的配置，不能把它们的选项误当成 Buildroot 本身的包选项。相应配置器可以这样打开：

```bash
make linux-menuconfig
make busybox-menuconfig
make uclibc-menuconfig   # 仅当当前配置使用 uClibc-ng
```

保存内核配置可用 `make linux-update-defconfig`；BusyBox 也有对应的 `busybox-update-config` 目标。具体目标会因当前配置而异，先执行 `make help` 或查看所选版本的手册。将精简后的 defconfig、内核/BusyBox 配置、补丁和 overlay 一起纳入版本控制；不要只提交 `.config`，也不要把本机绝对路径写进配置。

修改某个软件包后，可以先用它自己的目标重建，而不是立刻删除整个 `output/`：

```bash
make openssl-show-depends
make openssl-rebuild
make V=1
```

这里以已选中的 OpenSSL 包为例。`V=1` 会显示更完整的命令，便于发现编译器参数、头文件路径或链接库的问题。如果改动改变了包的配置或依赖，单次 rebuild 可能不足，按提示使用该包的 reconfigure/dirclean 目标，再让顶层 `make` 重建受影响的依赖。

## 8. 给镜像加入自己的文件和服务

Root filesystem overlay 适合加入少量默认配置、静态资源和启动脚本。overlay 的目录层次对应目标根目录：`board/demo/overlay/etc/...` 最后会成为客户机里的 `/etc/...`。本文的 `S99demo` 是 BusyBox init 的演示脚本；Buildroot 的 init 系统是可配置项，换成 systemd 时应按 systemd 的 unit 与包配置，不要把 BusyBox 的 `/etc/init.d/` 脚本当成通用服务定义。

overlay 不能代替软件包。正式应用应做成 Buildroot package，使源码版本、依赖、构建参数、安装路径和许可证信息可审查、可重建、可复用。自定义 package 一般由 `Config.in` 和 `.mk` 构成：前者定义 Kconfig 选项及依赖，后者描述源码获取、交叉编译、安装和许可证。团队可把这些文件放进 `BR2_EXTERNAL` 外部树，避免直接修改 Buildroot 上游树；外部树与产品 defconfig 一起纳入 Git。若产品需要不同 init、多个板型、镜像生命周期管理或大规模软件层复用，继续阅读[Yocto 从零构建篇](/posts/yocto-from-zero/)并评估它的元数据工作流。

## 9. 构建失败与启动失败，分开排查

| 现象 | 先看哪里 | 常见原因或下一步 |
| --- | --- | --- |
| 下载阶段报错 | `output/build/<包名>/`、`dl/`、终端最后一段错误 | 网络/代理、上游地址变化、校验值不符；确认错误发生在下载还是编译 |
| 找不到头文件或库 | 失败包的 `config.log`、`output/host/`、依赖菜单 | 依赖包未选中、配置缓存过期或 host 与 target 包混淆 |
| 链接到主机架构 | 失败命令中的编译器、`output/host/bin/` | 使用了主机 `gcc`；目标包必须用 Buildroot 提供的交叉工具链 |
| QEMU 找不到根文件系统 | 启动参数、镜像文件名、客户机 `/proc/cmdline` | 根设备名与 `if=virtio` 不匹配，或实际镜像格式/文件名不同 |
| 内核已启动但没有登录提示 | `console=` 参数、getty 配置、QEMU 图形窗口/串口 | 控制台选项不匹配；先使用该 defconfig 对应的板级说明 |
| 自定义文件没有进入镜像 | `.config` 中的 overlay 路径、overlay 内路径和权限 | overlay 选项未保存，路径相对目录错误，或启动脚本没有可执行权限 |

构建日志一般先显示真正失败的包。修复上游依赖、工具链选项或补丁后，再重建相关包；把“清空所有输出后重试”留给已确认状态损坏的情况，因为全量重建会重新消耗时间和下载流量。网络受限时可先运行 `make source` 下载已选配置需要的源码，再将下载目录带到构建环境。

## 10. 从 QEMU 演示走向可交付产品

QEMU 验证的是一套已选配置能否启动，不会验证真实板卡的 DDR 初始化、启动介质、GPIO、显示、无线、电源管理和量产刷写。移植到开发板时先索取厂商 BSP 与推荐版本，确认 SoC/ABI、Bootloader 先后阶段、内核 defconfig、设备树、根分区、分区表、串口与升级回滚机制。先启动最小系统，再分批加入驱动和应用，每一阶段保存可复现的镜像及串口日志。

交付前生成并审阅软件清单与许可材料：

```bash
make legal-info
```

检查 `output/legal-info/README` 的警告、组件清单和许可文本。该命令能收集辅助材料，但不能替代逐项许可证审查。版本库至少保存 Buildroot 固定版本/提交、defconfig、外部树、补丁、板级文件、应用源码版本和构建说明；持续集成应在干净 Linux 主机上实际构建，并保存最终镜像哈希。对于现场升级，还需另行设计签名验证、A/B 分区或恢复分区、失败回滚、密钥管理和安全更新策略，这些不由一次 `make` 自动提供。

## 11. 打开 Buildroot 源码树：Makefile、Kconfig 和软件包

Buildroot 看起来像一个大型 C 工程，容易让人误以为 `make` 最后会把 Buildroot 自己编译成 Linux。更准确地说，它是一个**构建编排器**：顶层 Makefile 读取 `.config`，按配置调用工具链、软件包、内核、Bootloader 和文件系统生成规则。大部分目标软件来自上游源代码；Buildroot 保存的是版本选择、配置片段、补丁和“怎样构建/安装它”的规则。

```text
Buildroot 源码树
├── Makefile / Config.in       顶层入口与配置系统
├── arch/                      CPU 架构、ABI 与架构默认值
├── toolchain/                 GCC、binutils、内核头文件、C 库
├── package/<name>/            用户态软件包的配置、构建规则和补丁
├── linux/、boot/              Linux 内核与 Bootloader 规则
├── system/                    根文件系统骨架、init 和系统配置
├── fs/                        ext2、tar、squashfs 等镜像生成规则
├── board/<vendor>/<board>/    板级 defconfig、内核配置、overlay、脚本
└── configs/                   可直接加载的 defconfig
```

一个常见软件包目录至少会有 `Config.in` 和 `<package>.mk`。前者向 Kconfig 注册 `BR2_PACKAGE_*` 选项及依赖，后者告诉包基础设施源码版本/位置、依赖、编译方式、目标安装规则和许可证信息；需要修补上游代码时还会有 `*.patch`，需要校验下载内容时配套 `.hash`。因此菜单里“看不到某个包”，可能是外部树没有加载、Kconfig 依赖不满足，或这个包并不支持当前架构/工具链，而不一定是 Makefile 出错。

顶层构建通常先准备主机侧工具和交叉工具链，再依赖关系构建目标库与应用、内核/可选 Bootloader，最后组装根文件系统并生成镜像。实际先后次序由依赖图决定，彼此独立的包可以并行；包的源码、编译现场和 stamp 状态通常在 `output/build/`。这也解释了为什么只改配置不一定让所有已编译包都自动重做：Buildroot 面向的是产品镜像集成构建，不是目标机上的通用软件包管理器。

把源码和构建结果分开，可以避免把个人配置或大体积输出混入上游树：

```bash
# 在 buildroot 源码树根目录执行；O 建议使用绝对路径
make O="$PWD/out-qemu" qemu_x86_64_defconfig
make O="$PWD/out-qemu" menuconfig
make O="$PWD/out-qemu"
```

此时配置文件也在 `out-qemu/.config`。保存产品的精简配置时使用 `make O="$PWD/out-qemu" savedefconfig BR2_DEFCONFIG="$PWD/board/demo/demo_defconfig"`。不要同时对同一个输出目录启动两个互相修改配置的构建；要并行验证多套配置，就为每套配置分配独立 `O=` 目录。

## 12. 交叉编译的关键：目标三元组、ABI 和 C 库

在开发机上输入 `gcc hello.c -o hello`，编译器通常生成能在开发机运行的程序。嵌入式产品需要的是另一种组合：构建过程运行在 x86_64 Linux 主机上，输出程序却可能运行在 ARM64 板卡上。交叉编译器负责生成目标架构的指令，并按目标的 ABI、浮点调用约定、C 库和头文件来编译/链接。

```text
Build machine: 运行 make / Buildroot 的 Linux 主机
Target:         最终运行程序的处理器、ABI、C 库与系统接口
Toolchain:      在主机上运行、但输出 Target 可执行文件的编译器与链接器
```

Buildroot 的 `output/host/` 名字容易让人误会成“目标机文件”。这里放的是**运行在构建主机上的工具**，包括交叉编译器、主机辅助工具和目标 sysroot；`output/staging/` 通常是该 sysroot 的兼容入口，供依赖库的包在编译时查找目标头文件与库。`output/target/` 则是待组装的目标根文件系统树；最终供刷机/启动的文件要从 `output/images/` 取，不能把前三者混作一谈。

内部工具链由 Buildroot 配置并构建，集成紧密，但改变 GCC、C 库或工具链关键选项往往需要重建整套系统。外部工具链适合芯片厂商已经提供固定 SDK、或组织已有验证过的工具链的场景；要确认架构、ABI、C 库、线程/C++ 等能力与 Buildroot 选项一致。不能简单拿开发机发行版自带的 `/usr/bin/gcc` 当成 ARM 工具链。

C 库实现了大部分用户程序调用的 libc API，并通过系统调用接口与 Linux 内核交互。Buildroot 可按版本和目标选择 glibc、musl 或 uClibc-ng；它们在体积、兼容性、功能和目标应用支持上有不同取舍。更换 C 库或其配置不是无害的小改动：已编译二进制的动态链接器、符号版本和 ABI 可能改变，通常要全量重建。内核头文件也参与工具链构建，选择的头文件版本不能比将来运行的内核接口更新到目标内核不具备的程度。

排查“程序编译成功但板上不能运行”，先看它到底为哪个架构/ABI 生成、依赖哪些动态库，而不是直接重编内核：

```bash
file output/target/usr/bin/hello-demo
readelf -h output/target/usr/bin/hello-demo
readelf -l output/target/usr/bin/hello-demo | grep interpreter
```

`file`/`readelf` 能检查 ELF 架构和动态加载器路径；主机上的 `ldd` 不能拿来验证一个不同架构的目标程序。应用团队若需在 Buildroot 之外独立开发，可用 `make sdk` 导出 SDK，并在构建说明中标注 SDK 对应的 Buildroot 配置、工具链和 sysroot；SDK 不是目标机的软件包管理器，也不会替代镜像版本管理。

## 13. 从上电到 PID 1：镜像里究竟有什么

“嵌入式 Linux 镜像”经常被当成一个文件来讲，其实至少要分清固件/Bootloader、内核、根文件系统以及启动参数。不同硬件的启动介质和阶段并不相同，Buildroot 可以根据配置构建其中若干部分，但不会凭一个 `make` 自动知道厂商板子的 DDR、时钟和 Flash 布局。

```text
常见真实板启动（示意，具体取决于 SoC）
Boot ROM → SPL/TPL（可选）→ U-Boot/其他 Bootloader
         → Linux kernel + DTB + 可选 initramfs
         → 挂载 rootfs → 执行 PID 1（init）→ 启动服务 / 登录

本文 QEMU 启动方式
QEMU -kernel bzImage → 直接启动 Linux
                    → virtio 磁盘上的 rootfs.ext2（root=/dev/vda）
                    → init → 用户空间
```

QEMU 命令里的 `-kernel output/images/bzImage` 是 direct-kernel boot：QEMU 把内核映像交给虚拟机直接启动，`-append` 将内核命令行传给内核，`-drive ... if=virtio` 提供虚拟磁盘。本例因此能检查内核识别 virtio 根盘、挂载 ext2、找到 init 并启动用户空间，但不会验证 BIOS/UEFI 如何搜寻启动设备，也不会验证 U-Boot 的环境变量、脚本、TFTP/SPI/eMMC 启动、DTB 传递或真实板级电源时序。需要验证这些环节，应选支持对应机器模型的 QEMU 启动方式，或在目标板串口上按厂商启动链做测试。

内核挂载根文件系统后，通常启动 `/sbin/init`（或由内核参数指定其他 init）。PID 1 再负责挂载必要的虚拟文件系统、设备节点管理、启动服务和提供登录入口。Buildroot 的默认方案是 BusyBox init；用户态最小不意味着应用就自动能工作：根文件系统还必须有正确的动态加载器、共享库、配置文件、设备节点/权限、DNS/时区/证书等产品需要的文件。

设备管理也是一个常被漏掉的连接点。内核 `devtmpfs` 可创建基础设备节点；简单系统可以先只用它，应用需要热插拔处理或固件加载时再评估 mdev/eudev；选择 systemd 时设备管理由 systemd/udev 路径处理。内核配置、Buildroot 的 `/dev` 管理选项与用户态服务要互相匹配。看到 `/dev/console` 存在，并不代表 I2C、网卡或自定义驱动已经正确工作。

## 14. 从空外部树加入一个 C 程序：BR2_EXTERNAL 实战

在 `output/target/` 临时复制一个二进制只能做一次性验证；下次全量清理就会消失，也无法清楚描述源码、依赖和许可证。产品代码更适合做成 Buildroot package，并把公司/项目定制放在独立的 `BR2_EXTERNAL` 树中。这样 Buildroot 上游代码可保持干净，应用包、板级文件和 defconfig 又能一起提交审查。

先准备并列的源码目录：

```text
workspace/
├── buildroot/                 # 固定到 2025.02.18
└── br2-external/
    ├── external.desc
    ├── Config.in
    ├── external.mk
    └── package/hello-demo/
        ├── Config.in
        ├── hello-demo.mk
        ├── S99hello-demo
        ├── hello-demo.service
        └── src/
            ├── main.c
            └── LICENSE
```

外部树至少需要名称描述、Kconfig 入口和 Makefile 入口。`external.desc` 的 `name: DEMO` 生成可供配置与 recipe 使用的 `BR2_EXTERNAL_DEMO_PATH`：

```text
name: DEMO
desc: Demo product packages
```

```make
# br2-external/Config.in
source "$BR2_EXTERNAL_DEMO_PATH/package/hello-demo/Config.in"
```

```make
# br2-external/external.mk
include $(sort $(wildcard $(BR2_EXTERNAL_DEMO_PATH)/package/*/*.mk))
```

`Config.in` 为 menuconfig 建立选择项；recipe 则使用 Buildroot 提供的 `generic-package` 基础设施，统一安排本地源码准备、依赖和目标安装步骤。

```kconfig
# br2-external/package/hello-demo/Config.in
config BR2_PACKAGE_HELLO_DEMO
    bool "hello-demo"
    help
      A small C example built with the target toolchain.
```

```c
/* br2-external/package/hello-demo/src/main.c */
#include <stdio.h>

int main(void)
{
    puts("Hello from a Buildroot target!");
    return 0;
}
```

下面的 recipe 演示最核心的一条数据流：`$(TARGET_CC)` 是目标交叉编译器；`$(@D)` 是 Buildroot 准备好的包源码目录；只把运行所需的可执行文件安装到 `$(TARGET_DIR)`。`.mk` 中的包名大写前缀必须与包名对应。把标准 MIT 许可证文本放在 `src/LICENSE`，并按真实项目修改版权与许可证；不要为了让 `legal-info` 不报警而随便填写许可证。

```make
# br2-external/package/hello-demo/hello-demo.mk
HELLO_DEMO_VERSION = 1.0
HELLO_DEMO_SITE = $(HELLO_DEMO_PKGDIR)/src
HELLO_DEMO_SITE_METHOD = local
HELLO_DEMO_LICENSE = MIT
HELLO_DEMO_LICENSE_FILES = LICENSE

define HELLO_DEMO_BUILD_CMDS
    $(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
        -o $(@D)/hello-demo $(@D)/main.c
endef

define HELLO_DEMO_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0755 $(@D)/hello-demo \
        $(TARGET_DIR)/usr/bin/hello-demo
endef

define HELLO_DEMO_INSTALL_INIT_SYSV
    $(INSTALL) -D -m 0755 $(HELLO_DEMO_PKGDIR)/S99hello-demo \
        $(TARGET_DIR)/etc/init.d/S99hello-demo
endef

define HELLO_DEMO_INSTALL_INIT_SYSTEMD
    $(INSTALL) -D -m 0644 $(HELLO_DEMO_PKGDIR)/hello-demo.service \
        $(TARGET_DIR)/usr/lib/systemd/system/hello-demo.service
endef

$(eval $(generic-package))
```

构建脚本会依据所选 init 系统调用相应的 `HELLO_DEMO_INSTALL_INIT_*` 规则。BusyBox/SysV 示例只在开机时运行一次并把输出送到控制台：

```sh
#!/bin/sh
# br2-external/package/hello-demo/S99hello-demo
case "$1" in
  start) /usr/bin/hello-demo >/dev/console 2>&1 ;;
  stop) ;;
  restart) "$0" stop; "$0" start ;;
  *) echo "Usage: $0 {start|stop|restart}" >&2; exit 1 ;;
esac
```

systemd 对应的 unit 可写成：

```ini
# br2-external/package/hello-demo/hello-demo.service
[Unit]
Description=Buildroot hello demo
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/hello-demo
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

在 Buildroot 源码树根目录加载外部树，再选择包并构建：

```bash
make BR2_EXTERNAL=../br2-external qemu_x86_64_defconfig
make BR2_EXTERNAL=../br2-external menuconfig
# 在 Target packages 的外部选项中启用 hello-demo，保存退出
make BR2_EXTERNAL=../br2-external hello-demo
make BR2_EXTERNAL=../br2-external
```

外部树相对路径按 Buildroot 源码树解释；生产脚本最好传绝对路径或由项目 Makefile 计算路径。`make hello-demo` 只构建这个 package，不等同于重打最终 rootfs；因此再运行顶层 `make` 生成镜像。启动 QEMU 后执行 `hello-demo` 验证二进制；如果同时安装了启动脚本/服务，再根据实际 init 用 `cat /proc/1/comm`、`systemctl status hello-demo.service` 或检查启动控制台输出来验证。修改应用源码后可用 `make hello-demo-rebuild all` 重新编译包并重打镜像。

这个最小示例故意使用裸 `$(TARGET_CC)`。实际项目应按上游构建系统选 Buildroot 的 autotools、CMake、Meson 等 package infrastructure；链接其他库时在 `.mk` 声明依赖，并区分“构建主机运行的工具”与“目标设备运行的库”。若应用需要头文件供其他 target package 编译使用，除了 `TARGET_DIR`，还要按需安装到 `STAGING_DIR`。

## 15. BusyBox init 和 systemd：同一个包要适配不同启动方式

init 是内核启动的第一个用户态进程，PID 必须为 1。Buildroot 默认选择 BusyBox init：它读取 Buildroot 的 `/etc/inittab`，执行 `/etc/init.d/rcS`，再按脚本名排序调用 `SNNname start`，同时按配置启动 getty。`SNN` 中的数字表达相对启动顺序，不是任意装饰；依赖网络的守护进程不能抢在网络配置脚本之前运行。

```text
内核挂载根文件系统
  → /sbin/init (BusyBox init, PID 1)
  → /etc/inittab
  → /etc/init.d/rcS
  → S01... → S40network → S50... → getty/login
```

前一节的脚本只展示 one-shot 启动动作，不是可靠的守护进程管理脚本。真正后台服务要处理重复启动、停止、PID 文件、返回码和日志；Buildroot 手册建议 daemon package 提供符合约定的 SysV/BusyBox 启动脚本，常用 `start-stop-daemon` 管理前台进程，并为能用的服务提供 systemd unit。服务的二进制、配置、运行账户、权限、启动文件和许可证最好由同一个 package 管理，而不是散落在几个 overlay 里。

切到 systemd 后，PID 1、设备管理、服务依赖与日志工具都会不同，并会引入 D-Bus、udev 等相应依赖，镜像不再等同于最小 BusyBox 组合。菜单中的 `System configuration → Init system` 决定系统 init；包的安装钩子仅安装所选 init 对应的文件。构建后验证时不要只看 unit 文件存在：检查 `cat /proc/1/comm`、`systemctl is-enabled hello-demo.service`、`systemctl is-active hello-demo.service` 与 `journalctl -u hello-demo.service -b`。若应用不需要 systemd 的服务依赖/设备管理能力，默认 BusyBox init 往往更轻；若产品依赖 D-Bus、复杂服务编排或 udev，再评估 systemd 的体积、启动行为和维护成本。

## 16. 增量构建不是“自动知道所有影响”：缓存与重建边界

Buildroot 会记录包的配置/构建阶段状态，但不会像完整发行版包管理器那样追踪每个已安装文件的所有反向影响。理解这一点，才能选择正确的重建范围：

| 改动 | 通常怎么做 | 为什么 |
| --- | --- | --- |
| overlay、post-build 或 post-image 脚本内容 | 重新运行顶层 `make` | 这些内容会在根文件系统组装/镜像阶段重新处理 |
| 自己的应用源码，且 build rules 未变 | `make hello-demo-rebuild all` | 重编该包并继续组装镜像 |
| 某包 configure 选项或依赖发生变化 | `make hello-demo-reconfigure all`，必要时 `dirclean` | 需要重新跑 configure，相关依赖变化可能还要重建消费者 |
| 从镜像中删除已安装软件包 | 通常全量清理后重建 | Buildroot 不维护每个包所安装文件的反向删除清单 |
| 工具链、C 库、架构 ABI 改变 | 评估并执行完整重建 | 编译器、头文件、动态加载器和库 ABI 会影响整套目标程序 |

包的下载/配置/编译日志通常在 `output/build/<包名>-<版本>/`；先从顶层 `make` 最后报告失败的包开始，查看该目录中的 `config.log`、`Makefile`、`*.stamp_*` 和具体编译命令。加 `V=1` 显示完整命令，有助于发现误用主机编译器、错误 sysroot、缺少头文件或链接次序问题。`make <包名>-show-depends` 可检查依赖，`make graph-depends` / `make graph-build` 可生成依赖/构建关系图（需按手册安装所需图形工具）。

不要把 `make clean` 当作通用“修复按钮”：它会丢弃大量可复用输出，并导致重新下载/编译。若删包、改 toolchain 或状态不确定，干净重建是可靠验证手段，但应清楚成本；常规应用开发更适合使用 `BR2_EXTERNAL` 和包级 rebuild。修改 overlay 后再次执行顶层 `make` 通常即可反映更改；直接编辑 `output/target/` 仅适合临时试验，下一次清理会丢失，最终要把改动迁回 overlay、recipe 或配置。

网络受限的团队可以先在联网环境运行 `make source` 下载当前配置所需源码，再把下载目录带到构建环境；构建前还要确认所有 Git 源引用固定到 commit/tag、归档有校验值、补丁被纳入版本控制。共享下载缓存 `BR2_DL_DIR` 能降低重复网络流量，但不能代替版本锁定或供应链审计。

## 17. 选择根文件系统格式：能启动和适合量产是两回事

`output/images/` 里的不同文件作用不同：内核是处理器要执行的映像；rootfs 是用户态目录树打包后的文件系统；Bootloader 镜像是特定启动链的组件；SD 卡/Flash 的整盘镜像可能再把分区表、boot 分区、内核和 rootfs 组合起来。文件名相近不代表可互换。刷写前要核对板卡的启动介质、分区偏移、镜像格式和厂商烧录工具，不能将 QEMU 的 `rootfs.ext2` 直接写入任意开发板。

常见文件系统输出可以这样理解：

| 格式 | 常见用途 | 需要提前考虑 |
| --- | --- | --- |
| `ext2`/`ext4` | QEMU 虚拟盘、SD/eMMC 上可读写 rootfs | 分区大小、掉电一致性、日志与磨损策略 |
| `squashfs` | 压缩、只读的固件 rootfs | 用户可变数据放哪里；是否需 overlayfs 或独立 data 分区 |
| `tar` | 归档/部署 rootfs 文件树 | 不是完整的可启动磁盘映像，设备节点/权限还要按目标方式处理 |
| `cpio` | initramfs/早期用户空间 | 内核如何获取它，以及后续切换到真实 rootfs 的方式 |

只读根文件系统并不会自动解决配置持久化：日志、网络配置、证书更新和用户数据要明确落到独立可写分区、tmpfs 或其他持久化介质。镜像类型、分区布局、内核 `root=`、initramfs 和 Bootloader 的启动参数必须作为一组设计，并在掉电/升级/空间不足等故障场景验证。

## 18. Buildroot 与 Yocto 怎么选：先看团队交付模型

“Buildroot 更小更简单、Yocto 只是更复杂”是过度概括。两者都能构建交叉工具链、内核和 rootfs；最终工作量取决于板厂 BSP、组件数量、产品维护年限和团队是否需要把系统拆成可复用的层。Buildroot 通过一个配置驱动较完整的产品构建，适合把明确的配置固化成一个最终镜像；Yocto/OpenEmbedded 通过 layer、recipe、class、distro 和 machine 元数据组织可复用的软件构建与发行版策略。两种方式都需要人来维护产品策略、升级和安全响应。

| 评估项 | Buildroot 常见做法 | Yocto/OpenEmbedded 常见做法 |
| --- | --- | --- |
| 入门路径 | defconfig + menuconfig + 一次完整镜像构建 | machine/distro/image 配置与多个 layer/recipe 解析 |
| 产品定制 | `BR2_EXTERNAL`、board 文件、package、overlay | 独立 layer、recipe、append、class、image/distro 配置 |
| 多产品复用 | 外部树和共享 package；产品配置之间仍需规划 | layer/recipe 元数据适合跨机型、发行版和团队复用 |
| 软件升级模型 | 常通过固定版本重新构建整套产品镜像 | 可围绕 recipe/包 feed/SDK 设计更细的产品流程 |
| 团队工程 | 适合目标明确、配置集中、版本受控的镜像工程 | 适合复杂 BSP、多产品变体、长期维护与标准化元数据流程 |
| 成本 | 配置和全量重建直观；产品规模扩大后要管理外部树与升级 | 前期概念/基础设施更多；层和配方治理得当时复用更系统 |

不要只按镜像大小选构建系统：通过裁剪依赖，两者都能生成精简 rootfs。先问：芯片厂是否提供哪个方案的 BSP？是否需要多个 SoC/板型共用应用？是否要维护多个产品发行版、SDK 和供应链清单？团队能否负责 recipe/layer 的持续升级？谁负责长期安全修复和回归测试？用同一块板、同一组软件、同一套更新需求做小规模验证，比单看菜单复杂度更可靠。

一个可交付的 Buildroot 项目至少把下面这些输入纳入 Git，并在 CI 的干净 Linux 主机上构建：

```text
Buildroot release/tag/commit + BR2_EXTERNAL commit
+ 产品 defconfig + 内核/BusyBox 配置 + board/ 文件
+ 本地 patch + 应用源码版本 + 下载校验/镜像策略
→ make → legal-info / manifest → 镜像哈希 → QEMU 或板级测试记录
```

不要提交可重建的 `output/` 代替源码清单；也不要只保存一个开发者的 `.config`，却没有外部树、补丁、内核配置和工具链选择。发行前审阅 `make legal-info` 的警告与 package manifest，保存 `sha256sum output/images/*` 结果，并在 CI 中实际验证启动。Buildroot 能帮助组织组件来源和构建，不会自动提供安全 OTA、镜像签名、密钥托管、A/B 更新、回滚和漏洞响应流程；这些是产品架构的一部分，必须明确所有者与测试场景。

## RK3588：让 Buildroot 使用 Rockchip kernel 默认分支

本文前面的 `qemu_x86_64_defconfig` 是 x86_64 演示，不能拿 RK3588 的 ARM64 内核替换它再期待 QEMU x86 启动。迁移到 RK3588 时，使用板卡匹配的 ARM64 defconfig、DTS、Bootloader 和 BSP 配置；Linux 源码选择 [Rockchip kernel 官方仓库](https://github.com/rockchip-linux/kernel)当前默认分支。本文核对时默认分支为 [`develop-6.1`](https://github.com/rockchip-linux/kernel/tree/develop-6.1)，该分支当时的 HEAD 为 `77168c8d5ab82399f65a80e9f807b50ba37cf483`，分支可能继续前进。

在 RK3588 产品的 Buildroot defconfig 中，内核来源可配置为：

```make
BR2_LINUX_KERNEL=y
BR2_LINUX_KERNEL_CUSTOM_GIT=y
BR2_LINUX_KERNEL_CUSTOM_REPO_URL="https://github.com/rockchip-linux/kernel.git"
BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION="develop-6.1"
BR2_LINUX_KERNEL_USE_DEFCONFIG=y
BR2_LINUX_KERNEL_DEFCONFIG="rockchip_linux"
BR2_LINUX_KERNEL_DTS_SUPPORT=y
BR2_LINUX_KERNEL_INTREE_DTS_NAME="rockchip/<board-dts-name-without-extension>"
```

`rockchip_linux` 对应该仓库 `arch/arm64/configs/rockchip_linux_defconfig`；DTS 值必须换成你实际板卡在 `arch/arm64/boot/dts/` 下的路径，不要照抄占位符。还要按板级 BSP 设置 toolchain、modules、内核镜像格式、设备树覆盖、Bootloader 和分区镜像，不能只改 kernel URL。Buildroot 的 `BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION` 支持 Git branch、tag 或 commit；如果使用 `develop-6.1`，两次构建之间默认分支内容可能变化。团队开发可跟随默认分支，但发版时应把解析出的 commit SHA 写入配置并保留工具链、defconfig、补丁与 DTS 一起评审。

配置完成后，使用 `make linux-menuconfig` 检查选项，退出后以 `make linux-update-defconfig` 保存到受版本控制的板级配置；确认 `.config`、内核 defconfig、实际构建 commit 和 `output/images/` 里的内核/DTB 相互匹配。本文的 QEMU x86 示例与 RK3588 板级构建是两条不同的验证路径。

参考：[Buildroot 官方手册](https://buildroot.org/downloads/manual/manual.html)、[2025.02 LTS 下载信息与维护版本](https://buildroot.org/download.html)、[QEMU direct Linux boot 说明](https://www.qemu.org/docs/master/system/linuxboot.html)、[QEMU 板级说明](https://gitlab.com/buildroot.org/buildroot/-/raw/2025.02.18/board/qemu/x86_64/readme.txt)、[Yocto 6.0.2 手动配置流程](https://docs.yoctoproject.org/6.0.2/dev-manual/poky-manual-setup.html)、[Rockchip kernel 默认分支](https://github.com/rockchip-linux/kernel)。本文使用维护中的 2025.02.18 LTS 作为可复现示例；其他 release 的 defconfig 和软件版本可能不同。延伸阅读：[PPSBBS 技术论坛原文](https://mp.weixin.qq.com/s/nGNtRB45EYnPZSHch7_56g) 与 [U-Boot/Linux Kconfig 核心机制](/posts/kconfig-uboot-kernel/)；本文重新组织和核对技术内容，不转载原文图表。

## 参考与下一篇

[下一篇：Yocto 从零构建](/posts/yocto-from-zero/) · [U-Boot 与 Linux 内核 Kconfig 核心机制](/posts/kconfig-uboot-kernel/) · [知识库首页](/knowledge-base/)
