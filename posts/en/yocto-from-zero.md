# Embedded Linux from scratch with Yocto Project 6.0.2

This article builds and boots a complete `qemux86-64` image from Yocto Project 6.0.2 (Wrynose), then adds a systemd service. QEMU validates the kernel, root filesystem, init, and application path; it does not replace the BSP, bootloader, device tree, and peripheral work needed for a real board.

## 1. Host and release prerequisites

Use a supported Linux host. The official `core-image-sato` reference lists about 140 GB free disk and 32 GB RAM; a minimal image is generally lighter but still needs ample resources. WSL2 is possible but not officially validated as a build host. On Ubuntu 24.04:

```bash
sudo apt update
sudo apt install -y build-essential chrpath cpio debianutils diffstat file \
  gawk gcc git iputils-ping libacl1 libcrypt-dev locales python3 \
  python3-git python3-jinja2 python3-pexpect python3-pip \
  python3-subunit socat texinfo unzip wget xz-utils zstd
locale -a | grep -i en_US.utf8
```

If the locale check fails, enable `en_US.UTF-8` following the official host instructions. Build as a normal user, not with `sudo bitbake`.

## 2. Get the pinned 6.0.2 layers

Follow the official manual Poky setup, pinning all three repositories to `yocto-6.0.2`:

```bash
mkdir -p embedded-yocto/layers
cd embedded-yocto
git clone -b yocto-6.0.2 https://git.openembedded.org/bitbake layers/bitbake
git clone -b yocto-6.0.2 https://git.openembedded.org/openembedded-core layers/openembedded-core
git clone -b yocto-6.0.2 https://git.yoctoproject.org/meta-yocto layers/meta-yocto
source layers/openembedded-core/oe-init-build-env
bitbake-getvar MACHINE
bitbake-getvar DISTRO
bitbake-getvar INIT_MANAGER
bitbake-layers show-layers
```

The setup script enters `build/`. Confirm `MACHINE` is `qemux86-64`. In 6.0.2, `nodistro` defaults to systemd, but Poky still defaults to SysVinit. If `INIT_MANAGER` is not `systemd`, add `INIT_MANAGER = "systemd"` to the demo's `build/conf/local.conf` before building the service image. Put this choice in a custom distro configuration for production.

## 3. Build and boot a minimal image

```bash
bitbake core-image-minimal
ls -lh tmp/deploy/images/qemux86-64/
runqemu qemux86-64 core-image-minimal ext4 nographic
```

If ext4 was not produced, check `bitbake-getvar IMAGE_FSTYPES` and select the actual image type. The first build fetches and compiles many dependencies. Do not commit `tmp/`, `downloads/`, or `sstate-cache/` as project source. In the QEMU guest:

```sh
uname -a
cat /proc/cmdline
cat /proc/1/comm
mount | grep ' on / '
```

Login policy depends on image configuration. For an isolated QEMU development image only, `EXTRA_IMAGE_FEATURES = "empty-root-password"` can allow an empty-password local console login. Never use that in a networked or production image, and do not enable empty-password SSH access. Shut down the guest with `poweroff` before continuing.

## 4. Put a service in the image

The repository's [meta-demo layer](https://github.com/yanruihe/yanruihe.github.io/tree/main/knowledge-base/examples/meta-demo) includes the `hello-yocto` recipe, script, unit, and `demo-image`. Back at the source directory:

```bash
cd ..  # only from embedded-yocto/build/
git clone --depth 1 https://github.com/yanruihe/yanruihe.github.io.git site
cp -a site/knowledge-base/examples/meta-demo layers/meta-demo
source layers/openembedded-core/oe-init-build-env
bitbake-layers add-layer ../layers/meta-demo
bitbake-layers show-recipes hello-yocto
bitbake demo-image
runqemu qemux86-64 demo-image ext4 nographic
```

Check `pwd` before the relative `cd ..`. Inside the guest:

```sh
cat /proc/1/comm
systemctl is-enabled hello-yocto.service
systemctl is-active hello-yocto.service
cat /run/hello-yocto/status
journalctl -u hello-yocto.service -b --no-pager
```

Expected states are `enabled` and `active`. If not, inspect `INIT_MANAGER`, package inclusion, unit installation, and journal output. The example image includes Dropbear for isolated development only; remove unnecessary SSH access and set an appropriate account/key policy before deployment. The recipe's `LICENSE = "CLOSED"` is a demonstration placeholder, not production license metadata.

## 5. Move from QEMU to a board

Record each repository commit, `MACHINE`, `DISTRO`, `INIT_MANAGER`, layer revisions, and image artifacts. Select a 6.0.2-compatible BSP for the target board and validate the bootloader, kernel configuration, device tree, partitions, console, networking, flashing, and rollback. Commit layers, recipes, and configuration; do not edit `tmp/work/` or deployed images as source. For build failures, inspect the relevant `temp/log.do_*`; for boot failures, inspect serial output, `systemctl status`, and `journalctl`.

References: [Yocto 6.0.2 host requirements](https://docs.yoctoproject.org/6.0.2/ref-manual/system-requirements.html), [manual setup](https://docs.yoctoproject.org/6.0.2/dev-manual/poky-manual-setup.html), [QEMU guide](https://docs.yoctoproject.org/6.0/dev-manual/qemu.html), and [6.0 init changes](https://docs.yoctoproject.org/6.0/migration-guides/migration-6.0.html).
