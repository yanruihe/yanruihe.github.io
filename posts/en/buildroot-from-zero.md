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

## 6. Follow the build from configuration to image

The menu is not a “compile all Linux source” switch. It records which parts the target product needs. `make qemu_x86_64_defconfig` writes a maintained set of choices into `.config`; `make menuconfig` changes those choices; the top-level Makefile then schedules package tasks according to their dependencies. The toolchain provides a target compiler, linker, and C library. User-space programs and libraries use that toolchain, while the kernel and bootloader are built from their own upstream source trees.

For example, when a selected network application depends on OpenSSL, Buildroot adds that dependency to the graph, prepares its target headers and libraries, and then cross-compiles the application. Each package `.mk` file describes where its source comes from, how to configure and build it, and which files to install. `Config.in` controls its appearance in the configuration menu. The root filesystem skeleton, selected packages, overlay, device table, and permissions form the target user space; a filesystem generator then packages them as ext2, tar, squashfs, or another selected format. Buildroot is the Makefile-driven integrator; the components remain independent projects.

| Stage | Main inputs | Typical result |
| --- | --- | --- |
| Configuration | defconfig, menuconfig, board settings | `.config`, kernel and BusyBox configuration |
| Toolchain | CPU/ABI, C library, compiler version | Cross tools under `output/host/bin/` |
| System components | kernel, optional bootloader, BusyBox, packages | Files installed into staging/target |
| Image generation | rootfs skeleton, overlay, device table, filesystem type | Bootable or flashable files under `output/images/` |

Buildroot can build its own toolchain or use an external cross-toolchain; the C library is a target choice. The QEMU example relies on virtual firmware to load the kernel, so it is useful for checking that the kernel and user space work together. A real board usually needs a matching bootloader, DDR and boot-media initialization, device tree, and vendor BSP. Decide early which parts Buildroot owns and which parts come from the board vendor.

## 7. Change configuration in small steps

After the first build, save a baseline and change one option at a time:

```bash
mkdir -p board/demo
cp .config board/demo/qemu_x86_64_base.config
make menuconfig
diff -u board/demo/qemu_x86_64_base.config .config
make
make savedefconfig BR2_DEFCONFIG=board/demo/demo_defconfig
diff -u configs/qemu_x86_64_defconfig board/demo/demo_defconfig
```

Common menus include **Target options** (architecture and ABI), **Toolchain** (C library and compiler), **System configuration** (hostname, password policy, init and device management), **Target packages**, **Kernel**, and **Filesystem images**. Start from the board and application requirements. Every extra package adds image size, dependencies, and maintenance or security work.

Linux, BusyBox, and the C library each have their own configuration. Their options are not Buildroot package options. Open the relevant configurator with:

```bash
make linux-menuconfig
make busybox-menuconfig
make uclibc-menuconfig   # only when using uClibc-ng
```

Save a kernel configuration with `make linux-update-defconfig`; BusyBox has a corresponding `busybox-update-config` target. Available targets depend on the configuration, so check `make help` or the manual for the pinned release. Commit the compact defconfig, kernel/BusyBox configuration, patches, and overlay together. Do not commit only a machine-specific `.config` or absolute paths from one developer's workstation.

After changing a package, rebuild its target before discarding the whole output directory:

```bash
make openssl-show-depends
make openssl-rebuild
make V=1
```

This example assumes OpenSSL is selected. `V=1` prints fuller commands, which helps reveal compiler flags, include paths, and link libraries. If the change affects configuration or dependencies, a rebuild alone may not be enough; use the package's reconfigure or dirclean target as appropriate, then let the top-level build refresh dependent packages.

## 8. Add your own files and services

A root filesystem overlay is useful for a small number of defaults, static files, or startup scripts. Its directory layout mirrors the target root: `board/demo/overlay/etc/...` becomes `/etc/...` in the guest. The `S99demo` script in this guide uses BusyBox init. Buildroot's init system is configurable; if you select systemd, use systemd unit files and package integration instead of treating a BusyBox `/etc/init.d/` script as a universal service definition.

An overlay is not a substitute for a software package. A production application should be a Buildroot package so its source version, dependencies, build flags, install paths, and license metadata can be reviewed and rebuilt. A custom package normally has a `Config.in` and a `.mk` file: the first defines its Kconfig option and dependencies; the second describes source retrieval, cross-compilation, installation, and license information. Put these files in a `BR2_EXTERNAL` tree rather than patching the upstream Buildroot tree directly, and version the external tree and product defconfig together. If your product needs multiple distributions, extensive metadata reuse, or a larger software-layer workflow, compare the [Yocto from-zero guide](/posts/en/yocto-from-zero/).

## 9. Separate build failures from boot failures

| Symptom | Inspect first | Likely cause or next step |
| --- | --- | --- |
| Failure during download | `output/build/<package>/`, `dl/`, final error lines | Network/proxy, upstream URL change, or checksum mismatch; identify whether fetch or compilation failed |
| Missing header or library | Failing package's `config.log`, `output/host/`, dependency menu | Dependency not selected, stale configure state, or confusion between host and target packages |
| Host architecture appears in a link command | Compiler command and `output/host/bin/` | Host `gcc` was used; target packages must use Buildroot's cross-toolchain |
| QEMU cannot find the root filesystem | QEMU arguments, image filename, guest `/proc/cmdline` | Root device does not match `if=virtio`, or the generated format/name differs |
| Kernel starts but there is no login prompt | `console=` arguments, getty configuration, QEMU terminal/window | Console mismatch; start with the board readme for the selected defconfig |
| Overlay file is absent in the image | Overlay path in `.config`, file mode, directory layout | Overlay option not saved, wrong relative path, or startup script is not executable |

Build logs usually identify the package that actually failed. Fix its dependency, toolchain choice, or patch, then rebuild the affected package. Reserve a full clean build for a confirmed corrupted state: it repeats compilation and downloads. On a restricted network, run `make source` to fetch sources selected by the current configuration, then move the download directory to the build host.

## 10. Move from the QEMU demo to a product

QEMU checks that the selected configuration boots. It does not validate board DDR setup, boot media, GPIO, display, wireless, power management, or factory flashing. For a development board, obtain the vendor BSP and supported versions first. Confirm the SoC/ABI, boot stages, kernel defconfig, device tree, root partition, partition table, serial console, and update/rollback design. Boot a minimal image, then add drivers and applications in batches while saving reproducible images and serial logs at each step.

Generate and review the software inventory and license material before release:

```bash
make legal-info
```

Review warnings, package manifests, and license texts in `output/legal-info/README`. This collects useful material, but it does not replace license-by-license review. At minimum, version the pinned Buildroot revision, defconfig, external tree, patches, board files, application source revisions, and build instructions. A clean Linux CI host should build the configuration and archive the resulting image hashes. Field updates also need separately designed signature checks, A/B or recovery partitions, rollback, key management, and security-update policy; one `make` does not provide them.

References: [Buildroot manual](https://buildroot.org/downloads/manual/manual.html), [2025.02 LTS releases and maintenance updates](https://buildroot.org/download.html), [QEMU board readme](https://gitlab.com/buildroot.org/buildroot/-/raw/2025.02.18/board/qemu/x86_64/readme.txt), and the [Yocto 6.0.2 manual setup](https://docs.yoctoproject.org/6.0.2/dev-manual/poky-manual-setup.html). This guide pins the maintained 2025.02.18 LTS for reproducible commands; defconfigs and package versions can differ across releases. Further reading: the [original PPSBBS article](https://mp.weixin.qq.com/s/nGNtRB45EYnPZSHch7_56g); this guide independently organizes and checks the technical material without reproducing its figures.
