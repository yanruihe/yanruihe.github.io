# Embedded Linux from scratch with Buildroot 2025.02.18

This walkthrough pins Buildroot 2025.02.18 LTS and uses `qemu_x86_64_defconfig` with QEMU. The goal is a bootable system, not just a cross-compiled application: Buildroot creates a toolchain, Linux kernel, and root filesystem. QEMU supplies virtual firmware. A real ARM board still needs its matching bootloader, device tree, drivers, and BSP.

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

The initial build downloads sources and builds the toolchain, target packages, kernel, and filesystem. Avoid assuming top-level `make -j` is needed. `output/build/` contains build work, `output/host/` contains host tools and the sysroot, and `output/images/` contains deployable artifacts. `output/target/` is not itself a bootable root filesystem.

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

Commit the defconfig, overlay, patches, and pinned versions, not the entire `output/` tree. For real hardware, select a matching board defconfig and verify CPU/ABI, bootloader, kernel configuration, device tree, partitions, serial console, and flashing procedure. A QEMU image is not directly flashable to an unrelated board. For build errors, inspect the failing package and `output/build/`; for boot errors, check kernel arguments, root device, and serial output. Handle source and license obligations before shipping.

References: [Buildroot manual](https://buildroot.org/downloads/manual/manual.html), [LTS release information](https://buildroot.org/download.html), and [QEMU board readme](https://gitlab.com/buildroot.org/buildroot/-/raw/2025.02.18/board/qemu/x86_64/readme.txt).
