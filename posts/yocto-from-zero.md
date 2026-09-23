# 从零构建嵌入式 Linux：Yocto Project 6.0.2

本篇使用 Yocto Project 6.0.2（Wrynose）在 `qemux86-64` 上从源码构建并启动一个完整镜像，再把一个 systemd 服务放进镜像。先在 QEMU 验证内核、根文件系统、init 和应用，再迁移到真实开发板；QEMU 成功不等于板级 BSP、Bootloader、设备树和外设已经适配。

## 1. 主机准备和版本边界

选择官方支持的 Linux 主机。Yocto 6.0.2 对 `core-image-sato` 的参考配置列出约 140 GB 空闲磁盘和 32 GB 内存；本篇的最小镜像通常更轻，但仍需充足空间。Windows 可使用 WSL2，但官方不把它列为经过验证的构建主机。下面以 Ubuntu 24.04 为例：

```bash
sudo apt update
sudo apt install -y build-essential chrpath cpio debianutils diffstat file \
  gawk gcc git iputils-ping libacl1 libcrypt-dev locales python3 \
  python3-git python3-jinja2 python3-pexpect python3-pip \
  python3-subunit socat texinfo unzip wget xz-utils zstd
locale -a | grep -i en_US.utf8
```

若最后一行无结果，先按官方主机要求启用 `en_US.UTF-8` locale。正常用户执行构建命令，不用 `sudo bitbake`。

## 2. 获取固定的 6.0.2 元数据

使用官方的手动 Poky 配置路径，三个仓库都固定到 `yocto-6.0.2`，避免把不同发行版的层混用：

```bash
mkdir -p embedded-yocto/layers
cd embedded-yocto
git clone -b yocto-6.0.2 https://git.openembedded.org/bitbake layers/bitbake
git clone -b yocto-6.0.2 https://git.openembedded.org/openembedded-core layers/openembedded-core
git clone -b yocto-6.0.2 https://git.yoctoproject.org/meta-yocto layers/meta-yocto
source layers/openembedded-core/oe-init-build-env
```

脚本会进入 `build/`。确认配置的 `MACHINE` 为 `qemux86-64`，并记录发行版与 init 管理器：

```bash
bitbake-getvar MACHINE
bitbake-getvar DISTRO
bitbake-getvar INIT_MANAGER
bitbake-layers show-layers
```

Yocto 6.0.2 的 `nodistro` 默认是 systemd，**Poky 默认仍是 SysVinit**。本篇后面要运行 systemd 服务；若当前 `INIT_MANAGER` 不是 `systemd`，在演练用 `build/conf/local.conf` 中加入 `INIT_MANAGER = "systemd"` 后再构建。正式项目应放到自己的 distro 配置中，不要未经检查就假定默认值。

## 3. 构建最小镜像并启动

```bash
bitbake core-image-minimal
ls -lh tmp/deploy/images/qemux86-64/
runqemu qemux86-64 core-image-minimal ext4 nographic
```

如果所选镜像没有生成 ext4 格式，先查 `bitbake-getvar IMAGE_FSTYPES`，改用实际生成的类型。首次构建会下载和编译大量依赖；不要把 `tmp/`、`downloads/` 和 `sstate-cache/` 当作源代码提交。在 QEMU 控制台登录后检查：

```sh
uname -a
cat /proc/cmdline
cat /proc/1/comm
mount | grep ' on / '
```

登录策略取决于镜像配置。仅在隔离的 QEMU 开发镜像上，可以通过 `EXTRA_IMAGE_FEATURES = "empty-root-password"` 允许本地控制台空密码登录；不要用于联网或生产镜像，也不要同时开启 SSH 的空密码登录。先在客户机 `poweroff`，再回到构建主机继续。

## 4. 将自己的服务放入镜像

仓库提供了可检查的 [meta-demo 示例层](https://github.com/yanruihe/yanruihe.github.io/tree/main/knowledge-base/examples/meta-demo)：`hello-yocto` Recipe 安装脚本与 unit，`demo-image` 把该包加入镜像。回到源目录并复制示例层：

```bash
cd ..  # 从 build/ 回到 embedded-yocto/
git clone --depth 1 https://github.com/yanruihe/yanruihe.github.io.git site
cp -a site/knowledge-base/examples/meta-demo layers/meta-demo
source layers/openembedded-core/oe-init-build-env
bitbake-layers add-layer ../layers/meta-demo
bitbake-layers show-recipes hello-yocto
bitbake demo-image
runqemu qemux86-64 demo-image ext4 nographic
```

这里的 `cd ..` 只适用于仍在 `embedded-yocto/build/` 时；先用 `pwd` 确认。目标机中验证：

```sh
cat /proc/1/comm
systemctl is-enabled hello-yocto.service
systemctl is-active hello-yocto.service
cat /run/hello-yocto/status
journalctl -u hello-yocto.service -b --no-pager
```

`systemctl` 应报告 `enabled`、`active`；否则先核对 `INIT_MANAGER`、镜像是否包含包、unit 安装路径及 `journalctl`。示例镜像带 Dropbear，仅用于隔离开发环境；部署前请关闭不需要的 SSH 服务，设置合适的账户/密钥策略。示例 Recipe 的 `LICENSE = "CLOSED"` 只是演示，发布产品须填写真实许可证信息。

## 5. 从 QEMU 迁移到开发板

记录三个仓库的 commit、`MACHINE`、`DISTRO`、`INIT_MANAGER`、所用 layer 修订和镜像产物。针对目标板选择兼容 6.0.2 的 BSP layer，然后检查 Bootloader、内核配置、设备树、分区布局、串口、网络、刷机与回滚流程。要改项目功能，提交 layer/recipe/config，不直接编辑 `tmp/work/` 或部署镜像。构建失败先看对应任务的 `temp/log.do_*`，运行失败先看串口、`systemctl status` 和 `journalctl`。

参考：[Yocto 6.0.2 主机要求](https://docs.yoctoproject.org/6.0.2/ref-manual/system-requirements.html)、[官方手动配置流程](https://docs.yoctoproject.org/6.0.2/dev-manual/poky-manual-setup.html)、[QEMU 使用](https://docs.yoctoproject.org/6.0/dev-manual/qemu.html)、[6.0 初始化系统变化](https://docs.yoctoproject.org/6.0/migration-guides/migration-6.0.html)。
