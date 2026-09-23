# meta-demo：Yocto 可运行示例层

本示例面向 Yocto Project 6.0.2，将脚本与 systemd unit 打包为 `hello-yocto`，并通过 `demo-image` 加入镜像。中英文说明分别见 [Yocto 知识库](../../yocto/) 和 [Yocto Knowledge Base](../../en/yocto/)。

```text
meta-demo/
├── conf/layer.conf
├── recipes-demo/hello-yocto/hello-yocto_1.0.bb
├── recipes-demo/hello-yocto/files/hello-yocto.sh
├── recipes-demo/hello-yocto/files/hello-yocto.service
└── recipes-core/images/demo-image.bb
```

在 Linux/WSL2 中准备相互兼容的 6.0.2 修订，并把本目录复制到 Yocto 工作区。6.0.2 的 `nodistro` 默认是 systemd，但 Poky 默认仍是 SysVinit。先检查当前配置；若当前不是 systemd、而镜像需要它，在产品 distro 配置中设置 `INIT_MANAGER = "systemd"`（演练可放在 `conf/local.conf`）；已有 systemd 配置则无需重复设置。从包含 `poky` 的目录运行：

```bash
source poky/oe-init-build-env build-demo
bitbake-getvar DISTRO
bitbake-getvar INIT_MANAGER
bitbake-layers add-layer /absolute/path/to/meta-demo
bitbake-layers show-recipes hello-yocto
bitbake demo-image
```

启动 QEMU 或目标板后运行 `systemctl is-enabled hello-yocto.service`、`systemctl is-active hello-yocto.service` 和 `cat /run/hello-yocto/status`。服务未运行时可用 `systemctl start hello-yocto.service` 并查看 `journalctl -u hello-yocto.service -b --no-pager`。本示例的 `LICENSE = "CLOSED"` 仅供本地练习；正式产品需填写真实许可证和相应校验信息，并核对 `LAYERSERIES_COMPAT_demo` 与 BSP 配置。
