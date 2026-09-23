# meta-demo：Yocto 可运行示例层

本示例整理自本地 `F:\MyBrain\yocto\examples\meta-demo`。它将脚本与 systemd unit 打包为 `hello-yocto`，并通过 `demo-image` 加入镜像。中英文说明分别见 [Yocto 知识库](../../yocto/) 和 [Yocto Knowledge Base](../../en/yocto/)。

```text
meta-demo/
├── conf/layer.conf
├── recipes-demo/hello-yocto/hello-yocto_1.0.bb
├── recipes-demo/hello-yocto/files/hello-yocto.sh
├── recipes-demo/hello-yocto/files/hello-yocto.service
└── recipes-core/images/demo-image.bb
```

在 Linux/WSL2 中准备兼容的 Poky 分支，并把本目录复制到 Yocto 工作区。从包含 `poky` 的目录运行：

```bash
source poky/oe-init-build-env build-demo
bitbake-layers add-layer /absolute/path/to/meta-demo
# 将 INIT_MANAGER = "systemd" 写入 conf/local.conf
bitbake-layers show-recipes hello-yocto
bitbake demo-image
```

启动 QEMU 或目标板后运行 `systemctl status hello-yocto.service` 和 `cat /run/hello-yocto/status`。本示例的 `LICENSE = "CLOSED"` 仅供本地练习；正式产品需填写真实许可证和相应校验信息，并根据所选发行版核对 `UNPACKDIR`、`LAYERSERIES_COMPAT_demo` 和 BSP 配置。
