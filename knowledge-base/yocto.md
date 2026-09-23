# Yocto 使用知识库

## 1. 核心概念

Yocto Project 不是一个固定发行版，而是一套用 OpenEmbedded 构建定制 Linux 系统的工具和元数据。日常工作中最重要的对象是：

- **BitBake**：解析元数据并执行任务。
- **Recipe（配方）**：描述源码、依赖、编译、安装和打包方式。
- **Layer（层）**：按功能隔离和组合配方、类、机器与发行版配置。
- **Machine**：描述目标硬件平台。
- **Distro**：描述发行版策略，例如初始化系统、工具链和默认特性。
- **Image**：描述最终要生成的系统镜像及其软件包集合。

常见关系可以简化为：

```text
Layer → Recipe → Package → Image
  └──── Machine / Distro 配置影响解析与构建结果
```

## 2. 初始化与第一次构建

下面是通用流程，实际使用时必须让 `poky`、BSP 层和其他层处于相互兼容的发行版分支：

```bash
git clone https://git.yoctoproject.org/poky
cd poky
git checkout <compatible-release-branch>
source oe-init-build-env build

bitbake-layers show-layers
bitbake core-image-minimal
```

构建前确认 `MACHINE`、`DISTRO`、下载目录和共享状态缓存配置。第一次构建通常需要较长时间，后续构建应尽量复用 `DL_DIR` 和 `SSTATE_DIR`。

## 3. 创建和接入自定义层

```bash
bitbake-layers create-layer ../meta-myproduct
bitbake-layers add-layer ../meta-myproduct
bitbake-layers show-layers
```

建议把产品定制放在独立层中，不直接修改 `poky` 或 `meta-openembedded`。一个常见目录结构如下：

```text
meta-myproduct/
├── conf/layer.conf
├── recipes-apps/
│   └── demo/demo_1.0.bb
├── recipes-core/images/
│   └── myproduct-image.bb
└── recipes-kernel/linux/
    └── linux-%.bbappend
```

层的 `README` 里应记录适配的 Yocto 分支、依赖层、机器、维护者和验证命令。

## 4. 配方与镜像

配方至少要明确源码、许可证、依赖和构建任务。对现有软件的定制优先使用 `.bbappend`，避免复制整份上游配方。把软件加入镜像时，可以在镜像配方中声明：

```bitbake
IMAGE_INSTALL:append = " demo"
```

变量覆盖语法与发行版版本有关；升级分支时要检查 override 语法、层兼容性和依赖变化，不要只凭旧项目经验复制配置。

## 5. devtool 开发闭环

开发应用或修改已有配方时，可用 `devtool` 缩短“修改—构建—部署—固化”循环：

```bash
devtool add https://example.com/project.git
devtool modify <recipe>
devtool build <recipe>
devtool deploy-target <recipe> root@<target-ip>

# 在源码仓库提交修改后，把补丁和配方变更固化到正式层
devtool finish <recipe> ../meta-myproduct
devtool reset <recipe>
```

部署到目标机前先确认 SSH、目标架构和运行时依赖；`devtool finish` 前确认源码仓库已经提交，避免把未审查的临时修改带入正式层。

## 6. 调试清单

```bash
# 查看最终变量值及其来源
bitbake -e <recipe> | less

# 查看任务依赖或执行单个任务
bitbake -g <recipe>
bitbake <recipe> -c compile

# 进入配方的开发 shell
bitbake <recipe> -c devshell

# 清理配方后重新构建
bitbake <recipe> -c cleansstate

# 查询已生成包的文件归属
oe-pkgdata-util find-path /usr/bin/<program>
```

遇到“找不到配方”先检查层是否加入、配方名是否正确；遇到“配置没有生效”先用 `bitbake -e` 确认变量来源；遇到“增量构建异常”再有针对性地清理任务，不要一开始删除整个构建目录。

## 7. 可复现与发布

- 固定 manifest、层分支或 commit，而不是只记录一个模糊的版本号。
- 记录 `MACHINE`、镜像目标、构建时间、构建主机和关键配置。
- 将自定义层、配方、补丁和 `conf` 配置放入 Git；不要提交 `tmp/`、`downloads/`、`sstate-cache/` 等大型生成目录。
- 发布前至少完成一次干净环境构建或在 CI 中验证，并保存镜像校验值。

参考：[Yocto Project 概览](https://docs.yoctoproject.org/overview-manual/concepts.html)、[创建层](https://docs.yoctoproject.org/dev/dev-manual/layers.html)、[编写新配方](https://docs.yoctoproject.org/dev-manual/new-recipe.html)、[devtool](https://docs.yoctoproject.org/dev-manual/devtool.html)、[BitBake 文档](https://docs.yoctoproject.org/bitbake/dev/singleindex.html)。
