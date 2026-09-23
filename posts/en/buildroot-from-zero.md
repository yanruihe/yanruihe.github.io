# Embedded Linux from scratch with Buildroot 2025.02.18

This walkthrough pins Buildroot 2025.02.18 LTS and uses `qemu_x86_64_defconfig` with QEMU. The goal is a bootable system, not just a cross-compiled application: Buildroot creates a toolchain, Linux kernel, and root filesystem. This QEMU example uses `-kernel` to boot the kernel directly, so it does not exercise the usual BIOS/UEFI or U-Boot firmware path. A real ARM board still needs its matching bootloader, device tree, drivers, and BSP.

## First, why can Buildroot build a whole system?

Buildroot does **not reimplement Linux in C**. It is primarily a framework of Makefiles, Kconfig configuration, scripts, and patches. The kernel, GCC, C library, and BusyBox are separate upstream projects. Buildroot selects versions and options, resolves package dependencies, fetches sources, cross-compiles components, installs them into a target filesystem, and produces the requested images. Thus `make` drives a configured build graph rather than one giant C program.

```text
Board defconfig → .config → toolchain (binutils / GCC / C library, or external)
                         → target packages (BusyBox and applications)
                         → kernel / optional bootloader → root filesystem → images
```

This is a **responsibility map**, not a strict task execution order. The `qemu_x86_64_defconfig` in this article builds a kernel and root filesystem, and QEMU's `-kernel` option starts the kernel directly; **this example does not build U-Boot or test firmware discovery of the kernel**. The C library is configurable rather than always musl. BusyBox supplies small userspace utilities and the default init, not the kernel or Buildroot itself.

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

Buildroot can build its own toolchain or use an external cross-toolchain; the C library is a target choice. The QEMU example uses direct kernel boot, so it is useful for checking that the kernel and user space work together but does not test firmware or bootloader discovery. A real board usually needs a matching bootloader, DDR and boot-media initialization, device tree, and vendor BSP. Decide early which parts Buildroot owns and which parts come from the board vendor.

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

## 11. Inside the Buildroot tree: Makefiles, Kconfig, and packages

Buildroot can look like a large C project, which may suggest that `make` compiles Buildroot itself into Linux. More precisely, it is a **build orchestrator**: the top-level Makefile reads `.config` and invokes rules for the toolchain, packages, kernel, bootloader, and filesystem images. Most target software comes from upstream projects. Buildroot maintains version choices, configuration fragments, patches, and the instructions for building and installing each component.

```text
Buildroot source tree
├── Makefile / Config.in       top-level entry and configuration system
├── arch/                      CPU architectures, ABI, architecture defaults
├── toolchain/                 GCC, binutils, kernel headers, C libraries
├── package/<name>/            userspace package config, build rules, patches
├── linux/, boot/              Linux kernel and bootloader rules
├── system/                    rootfs skeleton, init, system configuration
├── fs/                        ext2, tar, squashfs, and image-generation rules
├── board/<vendor>/<board>/    board defconfig, kernel config, overlay, scripts
└── configs/                   ready-to-load defconfigs
```

A typical package directory contains `Config.in` and `<package>.mk`. The former registers a `BR2_PACKAGE_*` option and its dependencies with Kconfig; the latter describes the source version/location, dependencies, build method, target installation, and license metadata. Upstream fixes may live in `*.patch`; downloads can be checked with a `.hash` file. If a package does not appear in menuconfig, the external tree may not be loaded, a Kconfig dependency may be unmet, or the package may not support the selected architecture/toolchain. It is not necessarily a Makefile bug.

The top-level build prepares host tools and the cross-toolchain, builds target libraries and applications according to their dependencies, optionally builds the kernel and bootloader, and finally assembles the root filesystem and images. The dependency graph determines the actual order; independent packages can build in parallel. Package sources, build workspaces, and stamp files are normally under `output/build/`. This also explains why changing a setting does not necessarily force every already-built package to rebuild: Buildroot is designed to integrate product images, not to act as a general package manager on the target device.

Separating source from output keeps personal settings and large build artifacts out of the upstream tree:

```bash
# Run from the Buildroot source root; an absolute O= path is recommended.
make O="$PWD/out-qemu" qemu_x86_64_defconfig
make O="$PWD/out-qemu" menuconfig
make O="$PWD/out-qemu"
```

The configuration is then in `out-qemu/.config`. Save a compact product configuration with `make O="$PWD/out-qemu" savedefconfig BR2_DEFCONFIG="$PWD/board/demo/demo_defconfig"`. Do not run two builds that modify the same output directory concurrently. To test several configurations in parallel, give each one its own `O=` directory.

## 12. Cross-compilation: target tuple, ABI, and C library

Running `gcc hello.c -o hello` on a development machine normally produces a program that runs on that machine. An embedded product has two different sides: the build runs on an x86_64 Linux host, while the result may run on an ARM64 board. A cross-compiler emits instructions for the target architecture and follows its ABI, floating-point calling convention, C library, and headers.

```text
Build machine: runs make and Buildroot on Linux
Target:        processor, ABI, C library, and interfaces where the program runs
Toolchain:     runs on the build machine but emits executables for the target
```

The name `output/host/` is easy to misread. It contains tools that **run on the build host**, including the cross-compiler, helper tools, and target sysroot. `output/staging/` is normally a compatibility entry to that sysroot, where packages find target headers and libraries while compiling. `output/target/` is the target rootfs staging tree. The final files for booting or flashing come from `output/images/`; these directories are not interchangeable.

Buildroot can create an internal toolchain or use an external one. The internal option is tightly integrated, but changing GCC, the C library, or a fundamental toolchain option often requires rebuilding the whole system. An external toolchain is useful when a chip vendor provides a fixed SDK or the organization already validates one. Check that its architecture, ABI, C library, thread/C++ support, and other capabilities match the Buildroot configuration. The host distribution's `/usr/bin/gcc` is not an ARM toolchain.

The C library implements most libc APIs used by applications and mediates their system-call interface to the Linux kernel. Buildroot can select glibc, musl, or uClibc-ng depending on version and target. They differ in size, compatibility, features, and application support. Switching libraries or changing their configuration is not a cosmetic edit: the dynamic loader, symbol versions, and ABI of existing binaries may change, so a full rebuild is usually required. Kernel headers also participate in toolchain construction; the selected headers must not advertise interfaces newer than those provided by the kernel that will run on the device.

When an application builds but will not run on the board, check its architecture/ABI and dynamic dependencies before rebuilding the kernel:

```bash
file output/target/usr/bin/hello-demo
readelf -h output/target/usr/bin/hello-demo
readelf -l output/target/usr/bin/hello-demo | grep interpreter
```

`file` and `readelf` inspect the ELF architecture and dynamic-loader path. Host `ldd` cannot validate a binary for a different architecture. Application teams that build outside Buildroot can export an SDK with `make sdk`; document the corresponding Buildroot configuration, toolchain, and sysroot. An SDK is not a target-side package manager and does not replace image version management.

## 13. From power-on to PID 1: what is in an image?

“Embedded Linux image” is often used as if it were one file, but it helps to separate firmware/bootloader, kernel, root filesystem, and boot arguments. The exact startup stages depend on the hardware. Buildroot can build some of them when configured, but one `make` cannot infer a vendor board's DDR setup, clocks, or flash layout.

```text
Common physical-board startup (illustrative; SoC-dependent)
Boot ROM → optional SPL/TPL → U-Boot or another bootloader
         → Linux kernel + DTB + optional initramfs
         → mount rootfs → start PID 1 (init) → services / login

This guide's QEMU startup
QEMU -kernel bzImage → direct Linux kernel boot
                    → rootfs.ext2 on virtio disk (root=/dev/vda)
                    → init → userspace
```

The QEMU argument `-kernel output/images/bzImage` uses direct-kernel boot: QEMU starts the supplied kernel, `-append` passes its command line, and `-drive ... if=virtio` supplies a virtual disk. This checks that the kernel detects the virtio root disk, mounts ext2, finds init, and starts userspace. It does not test BIOS/UEFI device discovery, U-Boot environment variables or scripts, TFTP/SPI/eMMC boot, DTB handoff, or real-board power sequencing. To test those stages, choose a QEMU machine and boot mode that model them, or use the target board's serial console and vendor boot procedure.

After mounting rootfs, the kernel normally starts `/sbin/init` (or another program specified on the kernel command line). PID 1 mounts required virtual filesystems, manages devices, starts services, and provides login. Buildroot defaults to BusyBox init. A minimal userspace still needs more than an app binary: include the correct dynamic loader, shared libraries, configuration, device permissions, DNS/time-zone/certificate files, and whatever else the product requires.

Device management is another easily missed connection. Kernel `devtmpfs` creates basic device nodes. A simple system can start with that alone; add mdev/eudev when hotplug events or firmware loading require it. With systemd, device handling uses the systemd/udev path. Kernel options, Buildroot's `/dev` management setting, and userspace services must agree. Seeing `/dev/console` does not prove that an I2C bus, network interface, or custom driver works.

## 14. Add a C program from an empty external tree: BR2_EXTERNAL

Copying a binary into `output/target/` is a one-off experiment: it disappears after a clean build and does not document its source, dependencies, or license. Product code belongs in a Buildroot package. Keep project-specific files in a separate `BR2_EXTERNAL` tree so the upstream Buildroot checkout remains clean while packages, board files, and defconfigs can be reviewed and versioned together.

Start with sibling source directories:

```text
workspace/
├── buildroot/                 # pinned to 2025.02.18
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

An external tree needs a descriptor plus Kconfig and Makefile entry points. `name: DEMO` in `external.desc` creates `BR2_EXTERNAL_DEMO_PATH`, available to configuration and package recipes:

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

The package's `Config.in` adds a menu option. Its recipe uses Buildroot's `generic-package` infrastructure to handle local sources, dependencies, build steps, and installation.

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

The recipe shows the essential data flow: `$(TARGET_CC)` is the target cross-compiler; `$(@D)` is the package's prepared source directory; only the runtime executable is installed into `$(TARGET_DIR)`. The uppercase prefix in `.mk` must correspond to the package name. Put the standard MIT license text in `src/LICENSE`, then replace the example copyright and license with the real project's metadata. Never invent a license merely to silence `legal-info`.

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

Buildroot calls the matching `HELLO_DEMO_INSTALL_INIT_*` hook for the selected init system. The BusyBox/SysV example runs once at boot and sends output to the console:

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

The systemd unit can be:

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

Load the external tree from the Buildroot source root, enable the package, and build it:

```bash
make BR2_EXTERNAL=../br2-external qemu_x86_64_defconfig
make BR2_EXTERNAL=../br2-external menuconfig
# Enable hello-demo in Target packages / external options, then save and exit.
make BR2_EXTERNAL=../br2-external hello-demo
make BR2_EXTERNAL=../br2-external
```

Relative `BR2_EXTERNAL` paths are interpreted from the Buildroot source root; production scripts should use an absolute path or compute it in a project Makefile. `make hello-demo` builds that package but does not itself recreate the final rootfs, so run the top-level `make` afterward. Boot QEMU and run `hello-demo`. If you installed startup integration too, verify it according to the chosen init using `cat /proc/1/comm`, `systemctl status hello-demo.service`, or the boot console. After editing the app source, `make hello-demo-rebuild all` recompiles the package and recreates the image.

This minimal example intentionally calls `$(TARGET_CC)` directly. Real packages should use Buildroot's autotools, CMake, Meson, or other matching package infrastructure. Declare dependencies in `.mk`, and distinguish tools that run on the build host from libraries used by target programs. If another target package needs your headers, install them to `STAGING_DIR` as well as installing runtime files to `TARGET_DIR`.

## 15. BusyBox init and systemd: one package, different startup methods

Init is the first userspace process started by the kernel, and its PID must be 1. Buildroot defaults to BusyBox init. It reads Buildroot's `/etc/inittab`, runs `/etc/init.d/rcS`, then invokes `SNNname start` scripts in name order and starts getty according to configuration. The `NN` value communicates relative startup order; a daemon that requires networking should not start before the network setup script.

```text
Kernel mounts root filesystem
  → /sbin/init (BusyBox init, PID 1)
  → /etc/inittab
  → /etc/init.d/rcS
  → S01... → S40network → S50... → getty/login
```

The previous section's script demonstrates a one-shot startup action, not a robust daemon manager. A real background service needs correct start/stop behavior, duplicate-start protection, PID handling, return codes, and logging. Buildroot's guidance is for daemon packages to provide a conforming SysV/BusyBox script, commonly using `start-stop-daemon` for a foreground process, and a systemd unit where appropriate. Keep the executable, config, runtime user, permissions, startup files, and license metadata together in the package instead of scattering them across overlays.

Switching to systemd changes PID 1, device management, service dependencies, and logging tools, and brings dependencies such as D-Bus and udev; the image is no longer the minimal BusyBox combination. `System configuration → Init system` selects the init system, and the package hooks install only the matching startup files. Do not verify only that a unit file exists: check `cat /proc/1/comm`, `systemctl is-enabled hello-demo.service`, `systemctl is-active hello-demo.service`, and `journalctl -u hello-demo.service -b`. If the product does not need systemd's service dependency or device-management features, the default BusyBox init is often lighter. If it needs D-Bus, complex service orchestration, or udev, evaluate systemd's size, startup behavior, and maintenance costs.

## 16. Incremental builds do not know every dependency: cache and rebuild boundaries

Buildroot tracks package build stages, but it does not maintain a package-manager-style reverse map of every installed file and every package affected by a change. Use the narrowest rebuild that is actually safe:

| Change | Typical action | Reason |
| --- | --- | --- |
| Overlay, post-build, or post-image script content | Run top-level `make` again | These inputs are processed while assembling the rootfs/images |
| Application source only, build rules unchanged | `make hello-demo-rebuild all` | Rebuild the package and then assemble the image |
| Package configure option or dependency changed | `make hello-demo-reconfigure all`, or `dirclean` if needed | Re-run configure; consumers may also need rebuilding |
| Remove an installed package from the image | Usually clean and rebuild | Buildroot does not keep a reverse list for deleting each package's installed files |
| Toolchain, C library, or architecture ABI changed | Consider a full rebuild | Compiler, headers, loader, and library ABI affect target programs broadly |

Package download/configure/build logs are usually under `output/build/<package>-<version>/`. Start with the package named in the final error from top-level `make`; inspect `config.log`, build files, `*.stamp_*`, and the failing command. Add `V=1` to show full commands and identify host-compiler leakage, a wrong sysroot, missing headers, or link-order problems. `make <package>-show-depends` inspects dependencies; `make graph-depends` and `make graph-build` can generate dependency/build graphs (install the graph tools required by the manual).

Do not use `make clean` as a universal repair button: it discards reusable output and may cause downloads and compilation to repeat. A clean rebuild is a reliable check after removing packages, changing the toolchain, or when state is uncertain, but understand its cost. Normal application development is better served by `BR2_EXTERNAL` and package-level rebuilds. Re-running top-level `make` after changing an overlay usually incorporates it; editing `output/target/` directly is only a temporary experiment and will be lost on cleanup. Move validated changes into an overlay, recipe, or configuration.

For restricted networks, run `make source` in a connected environment to fetch sources selected by the configuration, then move the download directory to the build host. Before release, pin Git sources to commits/tags, verify archive hashes, and version patches. A shared `BR2_DL_DIR` reduces repeated downloads but does not replace version pinning or supply-chain review.

## 17. Choose a root filesystem format: bootable is not the same as production-ready

Files under `output/images/` serve different purposes. The kernel image contains code for the processor; a rootfs image packages the userspace tree; a bootloader image is one component of a specific startup chain; a whole-disk SD/flash image may combine a partition table, boot partition, kernel, and rootfs. Similar filenames do not make these artifacts interchangeable. Before flashing, verify the board's boot media, partition offsets, image format, and vendor flashing utility. Never write the QEMU `rootfs.ext2` to an unrelated board.

Common filesystem outputs have different tradeoffs:

| Format | Typical use | Questions to answer |
| --- | --- | --- |
| `ext2`/`ext4` | QEMU virtual disk or writable SD/eMMC rootfs | Partition size, power-loss consistency, logging, and flash wear |
| `squashfs` | Compressed, read-only firmware rootfs | Where mutable data lives; whether overlayfs or a separate data partition is needed |
| `tar` | Rootfs file-tree archive/deployment | Not a bootable disk image; device nodes and permissions depend on deployment method |
| `cpio` | initramfs/early userspace | How the kernel receives it and whether/how the system pivots to a real rootfs |

A read-only root filesystem does not solve persistence by itself. Logs, network settings, certificate updates, and user data need a deliberate location on a writable partition, tmpfs, or another persistent medium. Filesystem type, partition layout, kernel `root=`, initramfs, and bootloader arguments are one design and should be tested under power loss, updates, and low-storage conditions.

## 18. Buildroot or Yocto? Choose by the delivery model

“Buildroot is smaller and simpler; Yocto is just more complex” is an oversimplification. Both can build a cross-toolchain, kernel, and rootfs. Real effort depends on the vendor BSP, component count, product lifetime, and whether teams need reusable layers. Buildroot drives a fairly complete product build from a configuration and suits a clearly defined image. Yocto/OpenEmbedded organizes reusable software builds and distribution policies through layers, recipes, classes, distro, and machine metadata. Neither removes the need to own product policy, upgrades, and security response.

| Concern | Common Buildroot approach | Common Yocto/OpenEmbedded approach |
| --- | --- | --- |
| Getting started | defconfig + menuconfig + complete image build | machine/distro/image settings and multiple layers/recipes |
| Product customization | `BR2_EXTERNAL`, board files, packages, overlays | layers, recipes, appends, classes, image/distro configuration |
| Reuse across products | External trees and shared packages; product configs still need governance | Layer/recipe metadata supports reuse across boards, distros, and teams |
| Software-update model | Often rebuild the complete product image from pinned inputs | Can build more granular workflows around recipes, package feeds, and SDKs |
| Team engineering | Good for a focused, centrally configured, version-controlled image | Good for complex BSPs, product variants, and long-lived standardized metadata |
| Cost | Direct configuration and full rebuilds; scale requires external-tree and upgrade discipline | More upfront concepts/infrastructure; well-governed metadata can improve reuse |

Do not choose only by image size: both can produce a small rootfs by trimming dependencies. Ask which build system the silicon vendor supports; whether several SoCs/boards must share applications; whether the team maintains multiple product distros, SDKs, and supply-chain inventories; whether it can maintain recipes/layers; and who owns security fixes and regression tests. A small evaluation on the same board, software set, and update requirements is more useful than comparing menu complexity.

A deliverable Buildroot project should version these inputs and build on a clean Linux CI host:

```text
Buildroot release/tag/commit + BR2_EXTERNAL commit
+ product defconfig + kernel/BusyBox configs + board files
+ local patches + application revisions + source hashes/mirror policy
→ make → legal-info / manifest → image hashes → QEMU or board test record
```

Do not version `output/` instead of the inputs, or keep only one developer's `.config` without the external tree, patches, kernel configuration, and toolchain choice. Before release, review `make legal-info` warnings and package manifests, save `sha256sum output/images/*`, and actually test the image in CI. Buildroot organizes component sources and builds; it does not automatically provide secure OTA, image signing, key custody, A/B updates, rollback, or vulnerability response. These are product architecture responsibilities that need owners and test cases.

References: [Buildroot manual](https://buildroot.org/downloads/manual/manual.html), [2025.02 LTS releases and maintenance updates](https://buildroot.org/download.html), [QEMU direct Linux boot](https://www.qemu.org/docs/master/system/linuxboot.html), [QEMU board readme](https://gitlab.com/buildroot.org/buildroot/-/raw/2025.02.18/board/qemu/x86_64/readme.txt), and the [Yocto 6.0.2 manual setup](https://docs.yoctoproject.org/6.0.2/dev-manual/poky-manual-setup.html). This guide pins the maintained 2025.02.18 LTS for reproducible commands; defconfigs and package versions can differ across releases. Further reading: the [original PPSBBS article](https://mp.weixin.qq.com/s/nGNtRB45EYnPZSHch7_56g); this guide independently organizes and checks the technical material without reproducing its figures.

## References and next article

[Next: Yocto from scratch](/posts/en/yocto-from-zero/) · [Knowledge Base](/knowledge-base/en/)
