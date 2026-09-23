# 从零构建嵌入式 Linux：Buildroot 2025.02.18

本篇选择 Buildroot 2025.02.18 LTS、`qemu_x86_64_defconfig` 和 QEMU。目标不是交叉编译某个单独程序，而是从源码生成交叉工具链、Linux 内核、根文件系统，最后启动并验证一个可运行的系统。QEMU 的虚拟 BIOS 负责早期引导；换成真实 ARM 板时，Bootloader、设备树和板级驱动还需要对应 BSP。

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

`output/build/` 是编译过程，`output/host/` 是主机工具链和 sysroot，`output/images/` 才是部署产物；不要把 `output/target/` 当成可直接启动的根文件系统。

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

提交 `demo_defconfig`、overlay、补丁及版本清单，不提交整个 `output/`。对真实板卡，先选择或编写匹配的 board defconfig，再确认 CPU/ABI、Bootloader、内核配置、设备树、存储分区、串口和刷机方式；QEMU 镜像不能直接刷入不相干的硬件。构建失败先读最后一个失败包的日志和 `output/build/`，启动失败先核对内核命令行、根设备和串口，避免无目的地清空整个输出目录。软件许可证和源代码提供义务须在发布前处理。

参考：[Buildroot 手册](https://buildroot.org/downloads/manual/manual.html)、[2025.02 LTS 下载信息](https://buildroot.org/download.html)、[QEMU 板级说明](https://gitlab.com/buildroot.org/buildroot/-/raw/2025.02.18/board/qemu/x86_64/readme.txt)。
