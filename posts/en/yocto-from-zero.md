# Embedded Linux from scratch with Yocto Project 6.0.2

This article builds and boots a complete `qemux86-64` image from Yocto Project 6.0.2 (Wrynose), then adds a systemd service. QEMU validates the kernel, root filesystem, init, and application path; it does not replace the BSP, bootloader, device tree, and peripheral work needed for a real board.

## Yocto build components: Poky, layers, recipes, and BitBake

The Yocto Project is not a Linux distribution that you install on the target. It is a set of projects and conventions for building embedded Linux. Poky is the reference distribution and integration layer; OpenEmbedded-Core supplies the core recipes and classes; BitBake reads the metadata and schedules tasks. A product build usually adds a board BSP layer, a product distribution layer, application layers, and an image recipe.

```text
MACHINE (hardware) + DISTRO (distribution policy) + IMAGE recipe (product content)
                                  ↓
                   .conf / .bb / .bbappend in layers
                                  ↓ BitBake resolves dependencies and tasks
     fetch → unpack → patch → configure → compile → install → package → image
                                  ↓
              boot and rootfs artifacts under tmp/deploy/images/<machine>/
```

A recipe describes how to fetch, patch, configure, compile, install, and package one piece of software. A layer is a versioned boundary for recipes, configuration, and patches. An image recipe decides which binary packages end up in the filesystem. BitBake expands the metadata into a task dependency graph and uses task signatures and shared state to skip work that has not changed. The result is a product system defined by hardware, distribution policy, and a selected software set, rather than a root directory assembled by hand.

| Term | Question it answers | Value in this guide |
| --- | --- | --- |
| `MACHINE` | What hardware, CPU, kernel, and boot settings are targeted? | `qemux86-64` |
| `DISTRO` | Which distribution policy, init, and global settings apply? | `poky` reference distro |
| Image | Which software belongs in the final root filesystem? | `core-image-minimal` / `demo-image` |
| Layer | Which configuration, recipes, and patches belong to a team or product? | `meta-yocto` / `meta-demo` |

## 1. Host and release prerequisites

Use a Linux host listed in the [Yocto 6.0.2 requirements](https://docs.yoctoproject.org/6.0.2/ref-manual/system-requirements.html). The official reference build for `core-image-sato` lists about 140 GB of free disk and 32 GB RAM; this guide builds the smaller `core-image-minimal`. I have verified a successful build on Ubuntu 24.04 under WSL2. For Ubuntu 24.04 in Docker, I recommend allocating 40 GB RAM to Docker. This is a practical recommendation, not an official Yocto minimum. The commands below use Ubuntu 24.04:

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
printf '\nINIT_MANAGER = "systemd"\n' >> conf/local.conf
bitbake-getvar MACHINE
bitbake-getvar DISTRO
bitbake-getvar INIT_MANAGER
bitbake-layers show-layers
```

The setup script enters `build/`. Confirm `MACHINE` is `qemux86-64`. Yocto 6.0.2's `nodistro` defaults to systemd; the Poky reference distro can select a different init. This guide uses Poky, so it explicitly sets `INIT_MANAGER = "systemd"` in `conf/local.conf` and confirms it with `bitbake-getvar INIT_MANAGER`. Put the choice in your own distro configuration instead of relying on each developer's `local.conf`.

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

## 6. Understand BitBake tasks and build directories

The argument to `bitbake core-image-minimal` is a recipe target, not a Linux kernel `make` target. BitBake parses the visible layers and configuration, then calculates task dependencies. A package build commonly includes tasks such as `do_fetch`, `do_unpack`, `do_patch`, `do_configure`, `do_compile`, `do_install`, and `do_package`. Tasks can run in parallel, and unchanged tasks can reuse `sstate-cache`. This is why the first build takes a long time while later changes often rebuild only affected tasks.

| Path | Purpose | Commit to product Git? |
| --- | --- | --- |
| `conf/local.conf`, `conf/bblayers.conf` | Local target settings and enabled layer list | Usually not as a personal build directory; move product defaults to a versioned layer/distro |
| `tmp/work/` | Recipe workspaces, compile output, and task logs | No; BitBake can recreate it |
| `tmp/deploy/images/<machine>/` | Kernel, bootloader, images, manifests, and other deployables | Archive as build output, not as source code |
| `downloads/` | Upstream source download cache | Share or cache when useful; normally not Git source |
| `sstate-cache/` | Reusable task output cache | May live on team infrastructure or workstations; not product source |
| `layers/*` | Recipes, configuration, patches, and metadata | Yes; record a fixed revision for every repository |

Inspect a variable's final value with `bitbake-getvar MACHINE` or `bitbake-getvar IMAGE_FSTYPES`. To inspect settings merged for a recipe, run `bitbake -e hello-yocto`; the output is large, so filter for the variable you need. Check which recipes and layers are visible with:

```bash
bitbake-layers show-layers
bitbake-layers show-recipes hello-yocto
bitbake -c listtasks hello-yocto
```

Run `bitbake -g demo-image` to generate dependency graph files that help explain why an image pulls in particular packages. After editing a recipe, build that recipe first (`bitbake hello-yocto`), then rebuild the image (`bitbake demo-image`). Do not delete all of `tmp/` or run a global clean as the first response to an error; start with the failing task's full log and expanded recipe variables.

## 7. Create your own layer and recipe

The earlier demo uses a real `meta-demo` layer. To practise from an empty directory instead of using the repository example, generate a separate layer skeleton inside an initialized Yocto environment, then add a recipe, service script, and unit:

```bash
bitbake-layers create-layer ../layers/meta-practice
bitbake-layers add-layer ../layers/meta-practice
bitbake-layers show-layers
```

A typical layout is:

```text
layers/meta-practice/
├── conf/layer.conf
├── recipes-demo/hello-yocto/hello-yocto_1.0.bb
├── recipes-demo/hello-yocto/files/hello-yocto.sh
├── recipes-demo/hello-yocto/files/hello-yocto.service
└── recipes-core/images/demo-image.bb
```

The recipe inherits the `systemd` class, declares local files, installs the script and unit, and sets `SYSTEMD_SERVICE:${PN}`. The image recipe adds the package through `IMAGE_INSTALL:append`. The demo service periodically writes a status file to `/run/hello-yocto/status`; its unit uses `Restart=on-failure`, and the QEMU guest verifies it with `systemctl` and `journalctl`. See the complete recipe, install rules, and image recipe in the [meta-demo example directory](https://github.com/yanruihe/yanruihe.github.io/tree/main/knowledge-base/examples/meta-demo). Replace its `LICENSE = "CLOSED"` placeholder with the project's real SPDX license and required checksum information.

You can rerun a task for one recipe, but understand the cache impact first: `-c clean` removes the work directory, while `-c cleansstate` also removes that recipe's shared-state cache and can make other builds slower. Use the latter only when you have evidence that cached state is the problem and accept the rebuild cost. For a team project, put MACHINE, DISTRO, init, and application choices in a versioned product layer. Use `bitbake-layers create-layers-setup` to capture the layer repositories and revisions, or use the manifest tool already adopted by your team, so everyone checks out the same set.

## 8. Common failures and how to locate them

| Symptom | Check first | Suggested action |
| --- | --- | --- |
| `do_fetch` fails | Proxy, DNS, URL, Git branch/tag, checksum | Confirm source access; do not switch to an unpinned `master` branch |
| `Nothing PROVIDES` | Layer inclusion, recipe name, `show-recipes` | Check `bblayers.conf` and layer dependencies; distinguish recipe, package, and image names |
| systemd is configured but PID 1 is not systemd | `bitbake-getvar INIT_MANAGER`, image distro configuration | Fix init before building and verify the intended build directory and distro |
| Package builds but service does not start | Package inclusion, unit path, `SYSTEMD_SERVICE` | Use `systemctl status` and `journalctl -u ... -b` to inspect unit and script errors |
| QEMU cannot start the image | Machine, image type, `runqemu` arguments | Check actual files under `tmp/deploy/images/qemux86-64/` and `IMAGE_FSTYPES` |
| Recipe changes have no effect | Selected layer/append, expanded variables, task log | Use `bitbake-layers show-appends` and `bitbake -e hello-yocto`, then rerun the required task |

The `tmp/work/<arch>/<recipe>/<version>/temp/` directory usually contains `log.do_*` and `run.do_*`: the first records task output, the second the task script. Start with the task BitBake reported as failed instead of guessing from the top of the log. If a service runs in QEMU but behaves incorrectly, inspect its journal, file permissions, runtime dependencies, and network settings.

## 9. Team builds, releases, and choosing a build system

For every releasable build, record revisions for BitBake, OpenEmbedded-Core, meta-yocto, the BSP, and product layers, as well as `MACHINE`, `DISTRO`, `INIT_MANAGER`, image target, source mirror/hash-server settings, and final artifact hashes. Reviews should check pinned `SRCREV` values or checksums, patch provenance, licenses, runtime dependencies, and whether services run with suitable privileges. `local.conf` is useful for experiments; product defaults belong in versioned distro, machine, image, and layer configuration so a clean CI host can reproduce them.

Buildroot is often a good fit when configuration is compact and one team produces a complete root filesystem image. Yocto is often a better fit for multiple boards and distro policies, shared layers across teams, and long-lived recipe and SDK maintenance. The real choice also depends on the silicon vendor's BSP, team experience, update plan, and support period. Neither system automatically supplies secure OTA, signing-key management, or factory rollback; those need separate designs and validation.

References: [Yocto 6.0.2 host requirements](https://docs.yoctoproject.org/6.0.2/ref-manual/system-requirements.html), [manual setup](https://docs.yoctoproject.org/6.0.2/dev-manual/poky-manual-setup.html), [writing a recipe](https://docs.yoctoproject.org/6.0.2/dev-manual/new-recipe.html), [layer guide](https://docs.yoctoproject.org/6.0.2/dev-manual/layers.html), [systemd class](https://docs.yoctoproject.org/6.0.2/ref-manual/classes.html#systemd), [QEMU guide](https://docs.yoctoproject.org/6.0/dev-manual/qemu.html), and [6.0 init changes](https://docs.yoctoproject.org/6.0/migration-guides/migration-6.0.html).
