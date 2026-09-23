# Embedded Linux from scratch with Buildroot 2025.02.18

This walkthrough pins Buildroot 2025.02.18 LTS and uses `qemu_x86_64_defconfig` with QEMU. The goal is a bootable system, not just a cross-compiled application: Buildroot creates a toolchain, Linux kernel, and root filesystem. QEMU supplies virtual firmware. A real ARM board still needs its matching bootloader, device tree, drivers, and BSP.

## First, why can Buildroot build a whole system?

Buildroot does **not reimplement Linux in C**. It is primarily a framework of Makefiles, Kconfig configuration, scripts, and patches. The kernel, GCC, C library, and BusyBox are separate upstream projects. Buildroot selects versions and options, resolves package dependencies, fetches sources, cross-compiles components, installs them into a target filesystem, and produces the requested images. Thus `make` drives a configured build graph rather than one giant C program.

```text
Board defconfig → .config → toolchain (binutils / GCC / C library, or external)
                         → target packages (BusyBox and applications)
                         → kernel / optional bootloader → root filesystem → images
```

This is a **responsibility map**, not a strict task execution order. The `qemu_x86_64_defconfig` in this article builds a kernel and root filesystem while QEMU provides virtual BIOS firmware; **this example does not build U-Boot**. The C library is configurable rather than always musl. BusyBox supplies small userspace utilities and the default init, not the kernel or Buildroot itself.

## 1. Prepare the host

Build as a normal user on Linux. Windows users can use a Linux VM or WSL2 on its Linux filesystem. The following is for Ubuntu 24.04; consult the [Buildroot host requirements](https://buildroot.org/downloads/manual/manual.html#requirement-mandatory) for other distributions. Allow ample disk, memory, and network capacity.

```bash
sudo apt update
sudo apt install -y build-essential git wget cpio unzip rsync file bc \
  bzip2 gzip xz-utils patch sed gawk qemu-system-x86
```

Use sudo only to install host packages, never for `make`.

## 2. Pin a release and build

```bash
git clone --branch 2025.02.18 --depth 1 https://gitlab.com/buildroot.org/buildroot.git buildroot
cd buildroot
git describe --tags --always
make qemu_x86_64_defconfig
make
ls -lh output/images/
test -s output/images/bzImage
test -s output/images/rootfs.ext2
```

The initial build downloads sources and builds the toolchain, target packages, kernel, and filesystem. Avoid assuming top-level `make -j` is needed. Keep the artifacts distinct:

| Path | Purpose |
| --- | --- |
| `.config` | Full configuration; `make savedefconfig` extracts a smaller board configuration for version control |
| `output/build/` | Per-component extraction, configuration, and compilation |
| `output/host/` | Host tools, cross-toolchain, and target sysroot; `output/staging/` is a compatibility symlink to that sysroot |
| `output/target/` | Almost the target filesystem, but lacking proper device nodes and some permissions; **do not deploy it** |
| `output/images/` | Kernel, root filesystem, and other final artifacts selected by the configuration |

## 3. Boot and inspect the system

Use the command from the selected board's [QEMU readme](https://gitlab.com/buildroot.org/buildroot/-/raw/2025.02.18/board/qemu/x86_64/readme.txt):

```bash
qemu-system-x86_64 -M pc \
  -kernel output/images/bzImage \
  -drive file=output/images/rootfs.ext2,if=virtio,format=raw \
  -append 'rootwait root=/dev/vda console=tty1 console=ttyS0' \
  -serial stdio -net nic,model=virtio -net user
```

The login prompt appears in the graphical QEMU window. Inside the guest, verify the kernel, root device, init, and root mount:

```sh
uname -a
cat /proc/cmdline
cat /proc/1/comm
mount | grep ' on / '
```

Shut down with `poweroff`. Do not hand-edit `output/images/rootfs.ext2` as a substitute for persistent configuration.

## 4. Add a boot-time action

The minimal Buildroot configuration uses BusyBox init, not systemd. Run `mkdir -p board/demo/overlay/etc/init.d` and create `board/demo/overlay/etc/init.d/S99demo` with:

```sh
#!/bin/sh
case "$1" in
  start) echo 'Buildroot demo is ready' >/dev/console ;;
  stop) ;;
  *) exit 1 ;;
esac
```

Run `chmod +x board/demo/overlay/etc/init.d/S99demo`, then `make menuconfig`. Set **System configuration → Root filesystem overlay directories** to `board/demo/overlay`, save, run `make`, and boot again. Look for `Buildroot demo is ready` and check `test -x /etc/init.d/S99demo` in the guest. A production application belongs in a Buildroot package with startup integration for its chosen init system; an overlay is only a small demonstration here.

## 5. Preserve configuration and move to hardware

```bash
make savedefconfig BR2_DEFCONFIG=board/demo/demo_defconfig
git status --short
```

Commit the defconfig, overlay, patches, and pinned versions, not the entire `output/` tree. A config file alone does not guarantee a byte-for-byte reproducible build: pin Buildroot and external source versions, patches, toolchain, and host environment. For real hardware, select a matching board defconfig and verify CPU/ABI, bootloader, kernel configuration, device tree, partitions, serial console, and flashing procedure. A QEMU image is not directly flashable to an unrelated board. For build errors, inspect the failing package and `output/build/`; for boot errors, check kernel arguments, root device, and serial output. Buildroot does not automatically solve OTA, security updates, or product lifecycle management. Handle source and license obligations before shipping. For layered metadata and distribution policy, compare the [Yocto from-zero guide](/posts/en/yocto-from-zero/).

References: [Buildroot manual](https://buildroot.org/downloads/manual/manual.html), [LTS release information](https://buildroot.org/download.html), and [QEMU board readme](https://gitlab.com/buildroot.org/buildroot/-/raw/2025.02.18/board/qemu/x86_64/readme.txt). Further reading: the [original PPSBBS article](https://mp.weixin.qq.com/s/nGNtRB45EYnPZSHch7_56g); this guide independently organizes and checks the technical material without reproducing its figures.
