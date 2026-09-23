# Yocto Knowledge Base

This guide targets Yocto Project 6.0.2 (Wrynose). Keep Poky, BSP, and other layers on compatible 6.0.2 revisions; a moving branch name alone is not enough for a reproducible build.

## Core concepts

Yocto Project is a set of tools and metadata for building customized Linux systems with OpenEmbedded.

- **BitBake** parses metadata and executes tasks.
- **Recipe** describes source, dependencies, compilation, installation, and packaging.
- **Layer** isolates and composes recipes and configuration.
- **Machine** describes target hardware; **Image** describes the final system image.

## Initialize and build

```bash
git clone https://git.yoctoproject.org/poky
cd poky
git checkout <matching-6.0.2-revision>
source oe-init-build-env build
bitbake-layers show-layers
bitbake core-image-minimal
```

Confirm that `poky`, BSP, and other layers use compatible 6.0.2 revisions. Record `MACHINE`, `DISTRO`, `DL_DIR`, and `SSTATE_DIR`.

## Custom layer and recipe

```bash
bitbake-layers create-layer ../meta-myproduct
bitbake-layers add-layer ../meta-myproduct
bitbake-layers show-layers
```

Keep product customizations in a separate layer. Prefer a `.bbappend` for existing software and use `IMAGE_INSTALL:append` to add packages to an image.

## devtool and debugging

```bash
devtool modify <recipe>
devtool build <recipe>
devtool deploy-target <recipe> root@<target-ip>
devtool finish <recipe> ../meta-myproduct
bitbake -e <recipe> | less
bitbake <recipe> -c devshell
oe-pkgdata-util find-path /usr/bin/<program>
```

Pin layer branches or commits, record build metadata, keep generated directories out of Git, and preserve image checksums for releases.

## 8. Practical example: add a systemd service to an image

This example provides a complete layer with a recipe, script, service unit, and image recipe:

The site repository includes the [downloadable meta-demo layer](../examples/meta-demo/README.md).

From a directory containing `poky`, enter the 6.0.2 build environment and check the init system:

```bash
source poky/oe-init-build-env build-demo
bitbake-getvar DISTRO
bitbake-getvar INIT_MANAGER
bitbake-getvar DISTRO_FEATURES
```

In 6.0.2, `nodistro` defaults to systemd, but Poky still defaults to SysVinit; a vendor distribution may choose differently. If `INIT_MANAGER` is already `systemd`, do not set it again. Only when the current build is not using systemd and the target image requires it, set `INIT_MANAGER = "systemd"` in the product distro configuration (or `conf/local.conf` for a demo) and rebuild the image.

```text
meta-demo/
├── conf/layer.conf
├── recipes-demo/hello-yocto/hello-yocto_1.0.bb
├── recipes-demo/hello-yocto/files/hello-yocto.sh
├── recipes-demo/hello-yocto/files/hello-yocto.service
└── recipes-core/images/demo-image.bb
```

The recipe installs the script and unit and enables the service. The image recipe adds the package with `IMAGE_INSTALL:append = " hello-yocto"`. The script updates `/run/hello-yocto/status` every ten seconds.

The unit's `ExecStart` points to the installed script, while `WantedBy=multi-user.target` identifies the boot target when the unit is enabled:

```ini
[Service]
Type=simple
ExecStart=/usr/bin/hello-yocto.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Key lines from the recipe are below:

```bitbake
SRC_URI = "file://hello-yocto.sh file://hello-yocto.service"
S = "${UNPACKDIR}"
inherit allarch systemd

do_install() {
    install -d ${D}${bindir} ${D}${systemd_system_unitdir}
    install -m 0755 ${UNPACKDIR}/hello-yocto.sh ${D}${bindir}/hello-yocto.sh
    install -m 0644 ${UNPACKDIR}/hello-yocto.service ${D}${systemd_system_unitdir}/hello-yocto.service
}
SYSTEMD_SERVICE:${PN} = "hello-yocto.service"
SYSTEMD_AUTO_ENABLE = "enable"
```

The full file also needs metadata such as `SUMMARY` and `LICENSE`; use real license information in production. In the build environment above, run:

```bash
bitbake-layers add-layer /path/to/meta-demo
bitbake-layers show-recipes hello-yocto
bitbake demo-image
```

Replace `/path/to/meta-demo` with the actual path. Choose `runqemu` arguments for your machine and image format, or boot the target board.

### Start the service at boot or manually

`inherit systemd`, `SYSTEMD_SERVICE:${PN}`, `SYSTEMD_AUTO_ENABLE = "enable"`, the unit's `[Install]` section, and the `hello-yocto` package in the image together make the service start on a fresh image. In 6.0.2 the `systemd` class enables services by default; the explicit `SYSTEMD_AUTO_ENABLE` makes that choice visible. On the target:

```bash
cat /proc/1/comm
systemctl is-enabled hello-yocto.service
systemctl is-active hello-yocto.service
cat /run/hello-yocto/status
journalctl -u hello-yocto.service -b --no-pager
```

`is-enabled` should return `enabled`, `is-active` should return `active`, and the timestamp in `/run/hello-yocto/status` should keep changing. If the unit is installed but not running, run on the target:

```bash
systemctl start hello-yocto.service
systemctl status hello-yocto.service
# Only on a development image with a writable root filesystem:
systemctl enable --now hello-yocto.service
```

Production images should enable the service in the recipe rather than rely on a runtime change.

For production, check the real license, non-root execution, and the BSP's init configuration. `LICENSE = "CLOSED"` in this example is for a local demo only.

## 9. Troubleshooting example: package built, service absent from image

Check each link in the chain: layer → recipe → package → image → runtime.

```bash
bitbake-layers show-layers
bitbake-layers show-recipes hello-yocto
bitbake -e demo-image | grep '^IMAGE_INSTALL='
oe-pkgdata-util find-pkg hello-yocto
```

If the recipe exists but `IMAGE_INSTALL` omits the package, check the image recipe and package name. If the package is present but the service does not start, inspect `INIT_MANAGER`, unit installation path, `SYSTEMD_SERVICE:${PN}`, `systemctl status`, and `journalctl`. Do not start by deleting all of `tmp/` or the shared cache.

References: [Yocto 6.0.2 init-manager migration notes](https://docs.yoctoproject.org/6.0.2/migration-guides/migration-6.0.html), [systemd class](https://docs.yoctoproject.org/6.0.2/ref-manual/classes.html#systemd), [6.0.2 variables](https://docs.yoctoproject.org/6.0.2/ref-manual/variables.html), and [creating layers](https://docs.yoctoproject.org/6.0.2/dev-manual/layers.html).
