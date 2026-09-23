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

References: [Yocto concepts](https://docs.yoctoproject.org/overview-manual/concepts.html), [creating layers](https://docs.yoctoproject.org/dev/dev-manual/layers.html), [writing recipes](https://docs.yoctoproject.org/dev-manual/new-recipe.html), and [devtool](https://docs.yoctoproject.org/dev-manual/devtool.html).
