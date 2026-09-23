# Yocto Knowledge Base

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
git checkout <compatible-release-branch>
source oe-init-build-env build
bitbake-layers show-layers
bitbake core-image-minimal
```

Confirm that `poky`, BSP, and other layers use compatible release branches. Record `MACHINE`, `DISTRO`, `DL_DIR`, and `SSTATE_DIR`.

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

Adapted from local `F:\MyBrain\yocto\examples\meta-demo` and `08-systemd服务案例.md`. This is a complete layer with a recipe, script, service unit, and image recipe:

The site repository includes the [downloadable meta-demo layer](../examples/meta-demo/README.md), so readers do not need access to the local `F:` drive.

```text
meta-demo/
├── conf/layer.conf
├── recipes-demo/hello-yocto/hello-yocto_1.0.bb
├── recipes-demo/hello-yocto/files/hello-yocto.sh
├── recipes-demo/hello-yocto/files/hello-yocto.service
└── recipes-core/images/demo-image.bb
```

The recipe installs the script and unit and enables the service. The image recipe adds the package with `IMAGE_INSTALL:append = " hello-yocto"`. The script updates `/run/hello-yocto/status` every ten seconds. Copy the local example layer into your Yocto workspace, then run in Linux/WSL2 from a directory containing `poky`:

Key lines from the local recipe are below; confirm that `UNPACKDIR` usage matches your Yocto release:

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

The full file also needs metadata such as `SUMMARY` and `LICENSE`; use real license information in production. Build it:

```bash
source poky/oe-init-build-env build-demo
bitbake-layers add-layer /path/to/meta-demo
# Set INIT_MANAGER = "systemd" in conf/local.conf
bitbake-layers show-recipes hello-yocto
bitbake demo-image
```

Replace `/path/to/meta-demo` with the actual path. `INIT_MANAGER` is a configuration-file setting, not a shell command. Choose `runqemu` arguments for your machine and image format, then verify on the target:

```bash
systemctl is-enabled hello-yocto.service
systemctl status hello-yocto.service
cat /run/hello-yocto/status
journalctl -u hello-yocto.service -b --no-pager
```

For production, check the real license, non-root execution, and the BSP's init configuration. `LICENSE = "CLOSED"` in this example is for a local demo only.

## 9. Troubleshooting example: package built, service absent from image

Following local `09-调试排错与构建加速.md`, check each link in the chain: layer → recipe → package → image → runtime.

```bash
bitbake-layers show-layers
bitbake-layers show-recipes hello-yocto
bitbake -e demo-image | grep '^IMAGE_INSTALL='
oe-pkgdata-util find-pkg hello-yocto
```

If the recipe exists but `IMAGE_INSTALL` omits the package, check the image recipe and package name. If the package is present but the service does not start, inspect `INIT_MANAGER`, unit installation path, `SYSTEMD_SERVICE:${PN}`, `systemctl status`, and `journalctl`. Do not start by deleting all of `tmp/` or the shared cache.

References: [Yocto concepts](https://docs.yoctoproject.org/overview-manual/concepts.html), [creating layers](https://docs.yoctoproject.org/dev/dev-manual/layers.html), [writing recipes](https://docs.yoctoproject.org/dev-manual/new-recipe.html), and [devtool](https://docs.yoctoproject.org/dev-manual/devtool.html).
