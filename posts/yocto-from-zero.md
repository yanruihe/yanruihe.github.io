# 从零构建嵌入式 Linux：Yocto Project 6.0.2

本篇使用 Yocto Project 6.0.2（Wrynose）在 `qemux86-64` 上从源码构建并启动一个完整镜像，再把一个 systemd 服务放进镜像。先在 QEMU 验证内核、根文件系统、init 和应用，再迁移到真实开发板；QEMU 成功不等于板级 BSP、Bootloader、设备树和外设已经适配。

## Yocto 的构建组成：Poky、层、配方与 BitBake

Yocto Project 不是一个可以直接安装到目标机上的 Linux 发行版，而是一组用于构建嵌入式 Linux 的项目和规范。Poky 是参考发行版与集成层，OpenEmbedded Core 提供基础配方和类，BitBake 读取这些元数据并安排任务。一个产品构建通常还会加入板级 BSP layer、产品 distro layer、应用 layer 和镜像配方。

```text
MACHINE（硬件） + DISTRO（发行版策略） + IMAGE recipe（产品内容）
                         ↓
           layers 中的 .conf / .bb / .bbappend
                         ↓ BitBake 解析依赖与任务
       fetch → unpack → patch → configure → compile → install → package → image
                         ↓
       tmp/deploy/images/<machine>/ 里的启动与根文件系统产物
```

Recipe 描述一个软件如何获取源码、应用补丁、配置、编译、安装和打包；layer 是这些 recipe、配置和补丁的版本化边界；image recipe 决定哪些二进制包最终进入镜像。BitBake 会把 recipe 展开成任务依赖图，并利用签名和共享状态缓存跳过未变化的工作。这里构建的是“硬件 + 发行版策略 + 软件包集合”共同定义的产品系统，不是手工把文件复制进根目录。

| 名称 | 负责回答的问题 | 本教程中的值 |
| --- | --- | --- |
| `MACHINE` | 目标硬件、CPU、内核和启动配置是什么？ | `qemux86-64` |
| `DISTRO` | 使用什么发行版策略、init 和全局配置？ | `poky` 参考发行版 |
| Image | 最终根文件系统要装哪些软件？ | `core-image-minimal` / `demo-image` |
| Layer | 哪些配置、recipe、补丁属于一个团队或产品？ | `meta-yocto` / `meta-demo` |

## 1. 主机准备和版本边界

选择[官方支持的 Linux 主机](https://docs.yoctoproject.org/6.0.2/ref-manual/system-requirements.html)。官方对 Yocto 6.0.2 的 `core-image-sato` 参考构建列出约 140 GB 空闲磁盘和 32 GB 内存；本文构建的是较小的 `core-image-minimal`。我已在 WSL2 的 Ubuntu 24.04 上实际构建验证通过。若使用 Docker 运行 Ubuntu 24.04，建议给 Docker 分配 40 GB 内存；这是实践建议，不是 Yocto 官方最低要求。下面以 Ubuntu 24.04 为例：

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
printf '\nINIT_MANAGER = "systemd"\n' >> conf/local.conf
```

脚本会进入 `build/`。确认配置的 `MACHINE` 为 `qemux86-64`，并记录发行版与 init 管理器：

```bash
bitbake-getvar MACHINE
bitbake-getvar DISTRO
bitbake-getvar INIT_MANAGER
bitbake-layers show-layers
```

Yocto 6.0.2 的 `nodistro` 默认使用 systemd；Poky 参考发行版可能选择不同的 init。本文使用 Poky，因此显式把 `INIT_MANAGER = "systemd"` 写入 `conf/local.conf` 并用 `bitbake-getvar INIT_MANAGER` 确认。正式产品应将选择写进自己的 distro 配置，而不是依赖开发者各自的 `local.conf`。

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

### RK3588：内核使用 Rockchip 仓库默认分支

前面的 `qemux86-64` 镜像使用 x86_64 目标内核，不能直接换成 ARM64 的 RK3588 内核。适配 RK3588 时，应使用支持该板的 BSP layer/MACHINE，并让该 BSP 的 kernel recipe 从 [Rockchip kernel 官方仓库](https://github.com/rockchip-linux/kernel)取源码。本文核对时仓库默认分支是 [`develop-6.1`](https://github.com/rockchip-linux/kernel/tree/develop-6.1)，HEAD 为 `77168c8d5ab82399f65a80e9f807b50ba37cf483`。

在 BSP 提供的 kernel recipe 或其 `.bbappend` 中，Git 源通常按以下方式声明；具体 recipe 名、补丁、defconfig 和 DTB 仍以所选 BSP 为准：

```bitbake
SRC_URI = "git://github.com/rockchip-linux/kernel.git;protocol=https;branch=develop-6.1"
SRCREV = "77168c8d5ab82399f65a80e9f807b50ba37cf483"
```

若通过 `.bbappend` 改已有 recipe，不要不加检查地用新的 `SRC_URI =` 覆盖原值；先确认 BSP 是否还从原 `SRC_URI` 引入补丁、defconfig、配置 fragment 或其他文件，再按对应 provider 的写法调整源码地址并保留这些输入。

`branch=develop-6.1` 明确选择该默认分支；示例中的 `SRCREV` 则固定到核对时的 HEAD，方便复现。若要在开发环境持续跟踪分支，可有意使用 `${AUTOREV}`，但构建结果会随远端移动，且需要额外考虑 BitBake 查询远端与缓存行为。发布构建应锁定经过验证的完整 commit SHA，并把 kernel、BSP layer、机器配置、内核 fragment 和 DTB 一起记录。不要把 ARM64 kernel 配进本文的 x86 QEMU `MACHINE`。

配置修改应通过 Yocto kernel 开发流程完成，而不是手工长期编辑 `tmp/work/.../.config`：在正确的 build 环境中对对应内核运行 `menuconfig`，用 `diffconfig`/配置 fragment 留下最小改动，并把 fragment 放入自有 layer。先检查最终 `virtual/kernel` provider、`SRC_URI`、`SRCREV`、`KERNEL_DEVICETREE` 与实际 machine，再构建并在 RK3588 板上验证启动日志和驱动枚举。Kconfig 依赖、defconfig 与驱动如何进入编译目标，另见 [U-Boot 与 Linux 内核 Kconfig 核心机制](/posts/kconfig-uboot-kernel/)。

## 6. 看懂 BitBake 任务与构建目录

`bitbake core-image-minimal` 的参数是一个 recipe 名称，不是 Linux 内核的 `make` 目标。BitBake 先解析可见 layers 和配置，再计算任务依赖；某个包的构建通常包含 `do_fetch`、`do_unpack`、`do_patch`、`do_configure`、`do_compile`、`do_install` 和 `do_package` 等任务。任务之间可能并行，未变化的任务会利用 `sstate-cache` 复用结果。因此第一次构建很慢，后续的小改动通常只重建受影响的任务。

常用目录：

| 路径 | 作用 | 应否提交到产品 Git |
| --- | --- | --- |
| `conf/local.conf`、`conf/bblayers.conf` | 本机目标设置与启用的 layer 清单 | 通常不直接提交个人 build 目录；将正式配置搬到受版本控制的 layer/distro |
| `tmp/work/` | 配方工作目录、编译现场、任务日志 | 否，可由 BitBake 重建 |
| `tmp/deploy/images/<machine>/` | 内核、bootloader、镜像、manifest 等部署产物 | 作为构建产物归档，不当作源代码维护 |
| `downloads/` | 上游源码下载缓存 | 可共享/缓存，通常不作为 Git 源文件提交 |
| `sstate-cache/` | 可复用的任务输出缓存 | 可放在团队缓存服务器或工作站，不作为产品源代码 |
| `layers/*` | recipe、配置、补丁和 layer 元数据 | 是；记录每个仓库的固定 revision |

想了解某个变量最终取值，用 `bitbake-getvar MACHINE` 或 `bitbake-getvar IMAGE_FSTYPES`；排查一个 recipe 合并了哪些设置，可用 `bitbake -e hello-yocto`，输出很长，可再筛选变量名。查看配方或 layer 是否可见：

```bash
bitbake-layers show-layers
bitbake-layers show-recipes hello-yocto
bitbake -c listtasks hello-yocto
```

查询任务图可对目标运行 `bitbake -g demo-image`，生成的依赖图文件可用于解释为什么一个镜像拉进了某些包。改完 recipe 后先构建单个 recipe（`bitbake hello-yocto`），确认后再重建 image（`bitbake demo-image`）。不要一遇到失败就删掉整个 `tmp/` 或运行全局清理；先看失败任务的完整日志与配方变量。

## 7. 从空目录创建自己的 Layer 和 Recipe

上面的示例通过 `meta-demo` 展示了一个真实 layer。若想从空目录练习（与使用仓库示例二选一），可在已加载 Yocto 环境时创建独立的 layer 框架，再把 recipe、服务脚本和 unit 放进去：

```bash
bitbake-layers create-layer ../layers/meta-practice
bitbake-layers add-layer ../layers/meta-practice
bitbake-layers show-layers
```

典型目录如下：

```text
layers/meta-practice/
├── conf/layer.conf
├── recipes-demo/hello-yocto/hello-yocto_1.0.bb
├── recipes-demo/hello-yocto/files/hello-yocto.sh
├── recipes-demo/hello-yocto/files/hello-yocto.service
└── recipes-core/images/demo-image.bb
```

Recipe 继承 `systemd` class，声明本地文件、安装脚本和 unit，设置 `SYSTEMD_SERVICE:${PN}`；image recipe 通过 `IMAGE_INSTALL:append` 把包加入系统。服务脚本写一个状态文件到 `/run/hello-yocto/status`，unit 以 `Restart=on-failure` 运行它，QEMU 中再用 `systemctl` 和 `journalctl` 验证。示例层的逐文件源码、安装规则和镜像 recipe 可在[meta-demo 示例目录](https://github.com/yanruihe/yanruihe.github.io/tree/main/knowledge-base/examples/meta-demo)查看；用它时把 `LICENSE = "CLOSED"` 替换成项目真实的 SPDX 许可证和对应校验信息。

调试时可以针对单个配方重跑任务，但先理解任务缓存语义：`-c clean` 清理工作目录，`-c cleansstate` 还会清掉该配方的共享状态缓存，后者会让其他构建也失去复用机会。只有在确认缓存造成错误且知道成本时才使用。对于反复手工配置的团队项目，可把 MACHINE、DISTRO、init、应用选择写入自有 layer；使用 `bitbake-layers create-layers-setup` 保存各层仓库与 revision 的清单，或采用团队已有的 manifest 工具，确保每个人检出同一组版本。

## 8. 常见故障与定位顺序

| 现象 | 先检查 | 建议动作 |
| --- | --- | --- |
| `do_fetch` 失败 | 代理、DNS、URL、Git branch/tag 和校验值 | 先确认构建主机能访问源码；不要直接改为不固定的 `master` |
| `Nothing PROVIDES` | layer 是否加入、recipe 名、`show-recipes` | 检查 `bblayers.conf` 与 layer 依赖，确认目标是 recipe/package/image 的正确名称 |
| 配置了 systemd 但 PID 1 不是 systemd | `bitbake-getvar INIT_MANAGER`、image 的发行版配置 | 在构建前固定 init 设置，确认镜像实际使用该 build 目录与 distro |
| 包构建成功但服务未启动 | 镜像是否安装包、unit 安装路径、`SYSTEMD_SERVICE` | 用 `systemctl status` 和 `journalctl -u ... -b` 查 unit 与脚本错误 |
| QEMU 不能启动镜像 | machine、镜像格式、`runqemu` 参数 | 查看 `tmp/deploy/images/qemux86-64/` 实际生成的文件及 `IMAGE_FSTYPES` |
| 修改了 recipe 但结果没变 | 命中的 layer/append、变量展开、任务日志 | `bitbake-layers show-appends`、`bitbake -e hello-yocto`，再按需要重跑具体任务 |

`tmp/work/<架构>/<recipe>/<版本>/temp/` 中通常包含 `log.do_*` 和 `run.do_*`：前者记录输出，后者记录任务执行脚本。先从 BitBake 最后报告的失败任务进入，而不是从日志最上方猜测。QEMU 内服务已启动但功能异常时，再检查服务日志、文件权限、运行时依赖和网络配置。

## 9. 团队构建、发布与方案选择

每次可交付构建都应记录 BitBake、OpenEmbedded-Core、meta-yocto、BSP 和产品 layer 的 revision，以及 `MACHINE`、`DISTRO`、`INIT_MANAGER`、镜像目标、源码镜像/哈希服务设置和最终产物哈希。代码审查关注 recipe 的固定 `SRCREV`/校验值、补丁来源、许可证、依赖是否进入镜像、服务是否以合适的用户权限运行。`local.conf` 适合本机试验；产品默认值放进版本化的 distro、machine、image 和 layer 配置，避免“开发者机器上能构建，CI 里不能复现”。

Buildroot 更适合配置相对集中、由一个团队产出完整 rootfs 镜像的项目；Yocto 更适合多板型、多发行版策略、多个团队共享 layer、长期维护配方与 SDK 的产品。实际选择还要考虑芯片厂商 BSP、现有团队经验、更新策略和维护周期。两者都不会自动给产品带来安全 OTA、签名密钥管理或量产回滚设计，这些需要单独定义和验证。

参考：[Yocto 6.0.2 主机要求](https://docs.yoctoproject.org/6.0.2/ref-manual/system-requirements.html)、[官方手动配置流程](https://docs.yoctoproject.org/6.0.2/dev-manual/poky-manual-setup.html)、[创建 Recipe](https://docs.yoctoproject.org/6.0.2/dev-manual/new-recipe.html)、[Layer 手册](https://docs.yoctoproject.org/6.0.2/dev-manual/layers.html)、[systemd class](https://docs.yoctoproject.org/6.0.2/ref-manual/classes.html#systemd)、[QEMU 使用](https://docs.yoctoproject.org/6.0/dev-manual/qemu.html)和[6.0 初始化系统变化](https://docs.yoctoproject.org/6.0/migration-guides/migration-6.0.html)。
