# 从零构建嵌入式 Linux：Buildroot 2025.02.18

本篇选择 Buildroot 2025.02.18 LTS、`qemu_x86_64_defconfig` 和 QEMU。目标不是交叉编译某个单独程序，而是从源码生成交叉工具链、Linux 内核、根文件系统，最后启动并验证一个可运行的系统。QEMU 的虚拟 BIOS 负责早期引导；换成真实 ARM 板时，Bootloader、设备树和板级驱动还需要对应 BSP。

## 先弄清原理：Buildroot 为什么能构建一整套系统？

Buildroot **不是用 C 语言重新实现 Linux**。它本身主要由 Makefile、Kconfig 配置、脚本和补丁组成；内核、GCC、C 库、BusyBox 等来自各自独立的上游项目。Buildroot 负责选择版本与选项、处理包之间的依赖、下载源码、交叉编译、安装到目标根文件系统，再生成指定格式的镜像。因此，`make` 触发的是一条受配置驱动的构建链，而不是编译一个巨大的 C 项目。

```text
板级 defconfig → .config → 工具链（binutils / GCC / C 库，或外部工具链）
                          → 目标软件（例如 BusyBox 和自己的应用）
                          → 内核 / 可选 Bootloader → 根文件系统 → 镜像
```

这是一张**职责图**，不是严格的任务执行顺序；具体组件取决于配置。本文的 `qemu_x86_64_defconfig` 生成内核和根文件系统，QEMU 使用虚拟 BIOS，**没有在这个示例中构建 U-Boot**。C 库也不是固定为 musl，可按配置选择 glibc、musl 或 uClibc-ng 等。BusyBox 提供精简用户空间工具和默认 init；它不是内核，也不是 Buildroot 本身。

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

Buildroot 能选择内置工具链，也能接入外部交叉工具链；C 库可按目标选择。QEMU 示例由虚拟机固件加载内核，适合先验证内核与用户空间协作。真实板卡通常要另外选对 Bootloader、DDR/启动介质初始化、设备树和厂商 BSP。哪些步骤由 Buildroot 管、哪些由板级厂商提供，要在开工时写清楚。

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

参考：[Buildroot 官方手册](https://buildroot.org/downloads/manual/manual.html)、[2025.02 LTS 下载信息与维护版本](https://buildroot.org/download.html)、[QEMU 板级说明](https://gitlab.com/buildroot.org/buildroot/-/raw/2025.02.18/board/qemu/x86_64/readme.txt)、[Yocto 6.0.2 手动配置流程](https://docs.yoctoproject.org/6.0.2/dev-manual/poky-manual-setup.html)。本文使用维护中的 2025.02.18 LTS 作为可复现示例；其他 release 的 defconfig 和软件版本可能不同。延伸阅读：[PPSBBS 技术论坛原文](https://mp.weixin.qq.com/s/nGNtRB45EYnPZSHch7_56g)；本文重新组织和核对技术内容，不转载原文图表。
