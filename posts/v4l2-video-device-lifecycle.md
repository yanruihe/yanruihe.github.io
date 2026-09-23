# V4L2 源码深度解析：从 `video_device` 到 `/dev/videoX` 的完整生命周期

从应用执行 `open("/dev/video0")` 开始，跟踪 Linux v6.1 V4L2 核心如何分配节点编号、注册字符设备、分发文件操作，并在设备注销后等到最后一个引用释放再回收对象。重点阅读 `drivers/media/v4l2-core/v4l2-dev.c`；图像格式协商、videobuf2 队列和传感器驱动只在需要划清边界时涉及。

## 1. 从一次 open 看完整路径

应用看到的是普通路径名，内核实际沿字符设备号找到 V4L2 节点，再由核心包装层调用驱动回调：

```text
open("/dev/video0")
  → 路径解析得到字符设备 inode 与 dev_t
  → dev_t 找到 cdev
  → cdev->ops 指向 V4L2 核心 v4l2_fops
  → v4l2_open() 按 minor 找到 video_device
  → video_get() 保住节点对象
  → video_device->fops->open()
  → 后续 read / ioctl / mmap / poll 由核心包装后转发
```

`v4l2-dev.c` 管理的是“节点怎样出现、怎样被访问、怎样退出”，不是摄像头采集引擎。它不因 `device_caps` 声明了 streaming 就自动创建缓冲区，也不代替驱动停止 DMA、中断或传感器。

## 2. 先区分节点、所属设备和一次打开

`struct video_device` 表示一个可对外提供 V4L2 文件接口的节点实例。一个物理设备可以有采集、输出、编解码等多个节点；它们可以关联同一个 `struct v4l2_device`，但有各自的节点编号、能力和操作表。

| 对象 | 生命周期和职责 | 不要与它混淆 |
| --- | --- | --- |
| `struct v4l2_device` | 组织一组 V4L2 节点、子设备和共享状态 | 不是 `/dev/videoX` 节点 |
| `struct video_device` | 一个 V4L2 字符设备节点的核心对象 | 不是整台摄像头，也不是每次打开的上下文 |
| 内嵌的 `struct device` | 设备模型身份、sysfs 层次和对象引用计数 | 不等于字符设备操作入口 |
| `struct cdev` | 把字符设备号连到一组 `file_operations` | 不负责设备模型名称和完整释放策略 |
| `struct file` / `file->private_data` | 一次打开形成的文件对象及驱动上下文 | 不等于共享的 `video_device` |
| `struct v4l2_fh` | 可选的标准 V4L2 文件句柄与事件关联 | 只有选择相应辅助接口才会创建 |
| `struct vb2_queue` | 驱动关联的视频缓冲区队列 | 有一个指针不代表队列已初始化或正在采集 |

读结构体时，关键是问清指针由谁创建、谁持有、最后由谁释放。把指针写入 `video_device` 不会复制目标对象，也不会自动转移其内存所有权。

### `fops` 与 `ioctl_ops` 分工不同

`video_device->fops` 是节点级的文件操作表，提供 `open`、`release`、`read`、`poll`、`mmap` 和 `unlocked_ioctl` 等入口。`video_device->ioctl_ops` 则是标准 V4L2 ioctl 命令回调表，例如 `vidioc_querycap`、`vidioc_s_fmt_vid_cap`、`vidioc_reqbufs` 和 `vidioc_streamon`。

常见的标准分发链是：

```text
应用 ioctl(fd, VIDIOC_..., arg)
  → 核心 v4l2_ioctl()
  → 节点 fops->unlocked_ioctl()
  → 驱动通常设置为 video_ioctl2()
  → 按命令、参数与格式类型分发到 ioctl_ops 中的 vidioc_*()
```

将 `unlocked_ioctl` 设为 `video_ioctl2` 是驱动选择的常见接法，不是只要填写 `ioctl_ops` 就自动发生。自定义 ioctl 分发可以走不同路径，不能假定它仍然使用标准回调表、有效命令位图和标准锁。

## 3. `/dev/video8` 中的 8，不一定是 minor 8

`video_device` 中有几种看起来相似的身份信息：

| 成员 | 含义 | 主要用途 |
| --- | --- | --- |
| `name` | 驱动提供的描述性名称 | sysfs 与媒体实体等描述 |
| `num` | 设备节点名称后缀 | 生成 `video8` 这样的设备模型名称 |
| `minor` | 字符设备次设备号 | `cdev_add()` 和核心 `video_devices[]` 查表 |
| `index` | 同一个 `v4l2_device` 下的节点索引 | 区分同一组中的多个节点 |

因此，路径 `/dev/video8` 的 `8` 是节点命名空间里的后缀，不是从路径文本直接传给驱动的参数。核心从 inode 的 `dev_t` 取出 minor，再据此查找节点。未启用固定 minor 区间时，`num` 和 `minor` 可以独立分配；启用 `CONFIG_VIDEO_FIXED_MINOR_RANGES` 时，映射规则又不同。调试时以 `stat` 显示的设备号和 sysfs 的 `dev` 属性为准，不要只按文件名猜测。

`vfl_type`、`vfl_dir` 与 `device_caps` 也不是同一维度：type 区分 video、radio、VBI 等节点类别；dir 表示接收、发送或 M2M 方向；caps 声明该节点支持的 V4L2 能力。声明某项能力不会替驱动实现相应回调。

## 4. 公共初始化不等于创建每个 video 节点

V4L2 核心初始化时会注册字符设备号范围并注册 `video4linux` 设备类。这个阶段只准备全局设施，不会为每个摄像头自动创建 `/dev/video0`。具体驱动稍后为每个节点构造 `video_device`，再调用 `video_register_device()`。

设备文件何时出现在 `/dev` 还涉及 Linux 设备模型和系统的 devtmpfs/udev 等设备节点管理机制。要分开理解三件事：`cdev_add()` 建立设备号到文件操作表的映射；`device_register()` 发布设备模型对象；节点管理机制让对应字符设备文件在 `/dev` 中可见。

## 5. 注册是分阶段发布，不是一个原子动作

驱动通常调用：

```c
ret = video_register_device(vdev, VFL_TYPE_VIDEO, -1);
```

在 Linux v6.1 中，这个公共接口进入 `__video_register_device()`。把源码按资源建立顺序读，比只背函数列表更容易定位并发和失败问题：

1. **检查调用契约并准备默认关联**：要求释放回调、所属 `v4l2_device` 和非子设备节点的能力信息有效；文件操作表及必需回调也必须已设置。初始化 `fh_lock`/`fh_list`，确定节点类别，并在父设备、控制处理器、优先级状态为空时继承上层关联。
2. **预留名称和设备号**：在 `videodev_lock` 下选择 `num`、`minor` 和同组 `index`，占用编号位图并把指针放进 `video_devices[minor]`。释放锁后，这个槽位虽然已被预留，但节点仍未对 V4L2 文件操作开放。
3. **准备标准 ioctl 有效集合**：若使用 `ioctl_ops`，核心按节点类别、方向、能力和可用回调形成候选集合。`v4l2_disable_ioctl()` 必须在注册前调用；在这段注册逻辑里，预置位表示要禁用，计算后位图才转成有效标准命令集合。
4. **建立字符设备入口**：分配 `cdev`，将它连接到统一的核心 `v4l2_fops`，设置模块 owner，再用 `cdev_add()` 将其关联到主/次设备号。所有节点共用核心包装层，随后才分发到各自的 `vdev->fops`。
5. **发布设备模型对象**：填写 class、dev_t、父对象和名称，调用 `device_register()`。这一步建立设备模型/sysfs 表示，并进入系统设备节点管理路径；它不是调用 `mknod()` 的 V4L2 专用替代写法。
6. **持有上层关联并完成可选媒体关联**：节点注册期间持有所属 `v4l2_device` 的引用；启用 Media Controller 时，还会按配置把节点接入媒体拓扑。媒体接口对象与 `/dev/videoX` 字符设备文件不是同一个东西。
7. **最后开放访问**：设置 `V4L2_FL_REGISTERED` 后释放管理锁并返回成功。打开路径会检查这个状态，所以编号已分配、全局表非空或 `cdev_add()` 已成功，都不能单独证明节点已完成激活。

```text
初始对象 → 编号预留 → ioctl 集合计算 → cdev 映射 → device/sysfs 发布
         → 上层/媒体关联 → 设置 REGISTERED → 允许新的 open
```

注册前必须完成回调会读取的状态、驱动私有指针和锁的初始化。节点发布后，另一个 CPU 可以在注册函数返回给调用者之后、甚至调用者下一条语句之前进入 `open()`。

### `num`、`minor` 和 `index` 的分配示例

假设某次构建未启用固定 minor 区间，先注册的节点可以拿到 `video8` 这个名称后缀，但全局字符设备表的第一个可用 minor 可能是 `0`；之后另一个类别的节点也可能占用 minor `1`。同一个 `v4l2_device` 下的 `index` 则独立从空位中分配。这个例子说明编号解决不同问题，不保证所有配置中都得到同样的数字。

`index` 也不是简单递增计数器：核心会扫描同一个 `v4l2_device` 关联的现存节点，找最小空位，所以之前节点最终释放后该 index 可以复用。

### 失败回滚与对象释放

失败路径只撤销已经取得的资源。编号预留后发生失败，核心清理已建立的 `cdev`、全局表项和编号；但 `video_register_device()` 失败时不会调用 `vdev->release`。驱动仍须按分配方式释放自己的节点对象：独立由 `video_device_alloc()` 分配的对象通常在失败分支调用 `video_device_release()`；内嵌在更大结构体中的对象应由匹配的外层生命周期管理。

不要把失败对象当成成功注册过的节点继续注销，也不要修改几个字段后盲目重复注册。内核接口文档明确说明，注册失败时调用方负责释放对象。

## 6. 打开路径：查表、检查、加引用要在同一个临界区

注册时核心写入：

```c
video_devices[vdev->minor] = vdev;
```

打开时，`video_devdata(file)` 使用文件 inode 的 minor 从同一张表取回对象。核心的关键步骤可以概括为：

```c
mutex_lock(&videodev_lock);
vdev = video_devdata(filp);
if (!vdev || !video_is_registered(vdev)) {
        mutex_unlock(&videodev_lock);
        return -ENODEV;
}
video_get(vdev);
mutex_unlock(&videodev_lock);

/* 复杂的驱动 open 回调不在全局节点管理锁内执行 */
if (vdev->fops->open)
        ret = vdev->fops->open(filp);
if (ret)
        video_put(vdev);
```

锁内的“查表 → 确认仍注册 → 取得对象引用”是一个交接整体。如果先查到指针、解锁、稍后才加引用，注销线程可能已经完成最终释放，打开线程就会解引用悬空指针。核心随后释放全局锁再调用驱动，是为了避免一个复杂甚至会睡眠的 `open()` 长时间阻塞所有节点管理操作。

锁与引用各司其职：锁保护状态交接，引用保护对象存活。核心再次检查注册状态，也不等于驱动回调和硬件注销从此完全互斥；驱动仍须为设备断开、流停止和正在执行的操作设计自己的同步。

不要混用三种取数方式：

- `video_devdata(file)`：取当前文件对应的 `video_device`。
- `video_get_drvdata(vdev)` / `video_drvdata(file)`：取节点关联的驱动私有数据。
- `file->private_data`：通常保存这一次 `open()` 创建的上下文；多次独立打开应各自处理。

核心不会替驱动自动填好 `file->private_data`，也不会替失败的驱动 `open()` 清理其已经分配的私有对象。

## 7. 文件操作包装层做什么、不做什么

成功打开后，核心包装操作被安装到当前文件操作路径。此后 `read()`、`ioctl()` 等不会重新走一遍字符设备 open 查找；核心先做节点状态/回调检查，再转给驱动。

| 操作 | 核心层主要职责 | 常见边界 |
| --- | --- | --- |
| `read` / `write` | 检查对应回调及注册状态，然后转发 | 不保证一帧完整复制，也不负责自动等待帧 |
| `mmap` | 检查回调及节点状态，再调用驱动映射 | 不自动分配缓冲区；具体映射常由驱动/VB2 接管 |
| `unlocked_ioctl` | 转发到节点文件操作表 | 标准命令通常还要由 `video_ioctl2()` 按 `ioctl_ops` 分发 |
| `poll` | 转发事件等待或返回相应默认/错误事件掩码 | 不会仅凭 `queue` 指针判断“有帧可读” |
| `release` | 调驱动关闭回调，最后归还核心打开引用 | 即使节点已注销，旧文件仍须完成关闭清理 |

所以遇到 `-ENOTTY`，要沿文件级 ioctl 回调、标准 `video_ioctl2()` 分发、`valid_ioctls` 筛选和具体 `vidioc_*` 实现逐层查，不能只根据最终 errno 断言是哪一层拒绝。`valid_ioctls` 也不是对任意私有 ioctl 的通用授权表。

## 8. 注销：关闭新访问，不是立刻 free

正常移除节点时调用 `video_unregister_device(vdev)`，而不是直接撤销内部 cdev 或手动清理核心全局表。v6.1 的主要顺序是：

1. 在 `videodev_lock` 下清除 `V4L2_FL_REGISTERED`，使后续正常 open 不能再取得新的节点引用。
2. 对使用标准 `v4l2_fh` 事件机制的节点唤醒等待者，让它们重新检查设备状态。
3. 调用 `device_unregister()` 撤下设备模型对象，并归还注册阶段持有的那份引用。

仍然打开的文件可能继续存在，随后需要走各自的 `release()` 清理。`device_unregister()` 返回时，vdev 可能已经最终释放，也可能仍被旧文件引用；调用者不能仅凭“函数刚返回”判断对象还活着。内核文档也指出，注销后不再接受新 open，旧文件操作（release 除外）会报错；最后一个用户退出时才调用节点最终释放回调。

注销不等于驱动硬件已安全停止。停止 DMA、同步/屏蔽中断、唤醒自有等待队列、阻止新的队列提交以及处理热拔出，仍由具体驱动和相关框架负责。`V4L2_FL_REGISTERED` 是节点访问准入状态，不是硬件健康或 streaming 状态。

## 9. 多个 release/引用，不要看名字猜职责

V4L2 这条路径上至少要区分：

| 回调/操作 | 作用对象 | 触发时机 |
| --- | --- | --- |
| `vdev->fops->release(file)` | 一次打开的驱动文件上下文 | 文件对象最终关闭时，可能多次发生 |
| 核心 `v4l2_release()` / `video_put(vdev)` | 归还成功 open 持有的节点引用 | 驱动 release 之后，无论它是否返回错误 |
| `v4l2_device_release(struct device *)` | V4L2 核心注册资源 | 节点 `struct device` 的引用归零时 |
| `vdev->release(vdev)` | 节点本身/驱动私有存储 | 核心清理完成后的最终释放 |
| `v4l2_device_put()` | 上层 V4L2 组织对象 | 节点最终释放逻辑按其生命周期约定归还 |

在只考虑注册引用和两个成功打开引用的简化例子里：注册后引用示意为 1，文件 A 打开后为 2，文件 B 打开后为 3；注销归还注册引用后为 2；A、B 各自最终关闭再归还后，计数才可能到 0。实际计数还可能包含设备模型和其他临时引用，这只是用来理解配对关系的示意，不是代码中固定的计数公式。

核心最终回调需通过内嵌关系从 `struct device` 找回 `video_device`，再清理 `video_devices[minor]`、`cdev`、名称编号以及适用的媒体关联，之后调用驱动提供的 `vdev->release`。编号要保留到最后：如果注销时就把旧 minor 立即复用，旧文件稍后关闭时仍可能凭 inode 中的旧 minor 查表，映射到错误的新节点。

### 为什么 `release` 不止一个

- `fops->release` 是“这一次打开结束”，清理每个文件上下文。
- `vdev->release` 是“节点对象最终结束”，可能释放 `video_device` 或内嵌它的外层对象。
- `struct device` 的 `.release` 先由 V4L2 核心接管，用来撤销核心维护的登记关系。

对独立分配对象使用 `video_device_release`；静态对象或外层嵌入对象应采用适合其布局的回调。成功注销之后，不要再无条件直接调用 `video_device_release(vdev)`，否则可能与仍在运行的文件引用发生 use-after-free 或 double-free。

## 10. 一个节点的注册组织示例

下面只展示节点与框架接口如何连接，不是完整可编译的摄像头驱动。`ctx`、队列、锁、操作表和硬件初始化都由驱动提供；`ctx` 与回调表必须在节点可能被使用期间保持有效。

```c
static int example_register_node(struct example_device *ctx)
{
        struct video_device *vdev;
        int ret;

        vdev = video_device_alloc();
        if (!vdev)
                return -ENOMEM;

        strscpy(vdev->name, "Example Capture", sizeof(vdev->name));
        vdev->v4l2_dev = &ctx->v4l2_dev;
        vdev->fops = &example_fops;
        vdev->ioctl_ops = &example_ioctl_ops;
        vdev->release = video_device_release;
        vdev->vfl_dir = VFL_DIR_RX;
        vdev->device_caps = V4L2_CAP_VIDEO_CAPTURE_MPLANE |
                            V4L2_CAP_STREAMING;
        vdev->lock = &ctx->lock;
        video_set_drvdata(vdev, ctx);

        /* 回调可能读取的反向指针，应在发布节点前准备好。 */
        ctx->vdev = vdev;

        ret = video_register_device(vdev, VFL_TYPE_VIDEO, -1);
        if (ret) {
                ctx->vdev = NULL;
                video_device_release(vdev);
                return ret;
        }

        return 0;
}
```

成功退出路径先由驱动协调硬件停止和运行中操作，再调用 `video_unregister_device(ctx->vdev)`。节点的最终存储释放交给引用与 `vdev->release` 回调；若 `ctx` 生命周期不能覆盖所有仍打开的文件，就还需要上层引用或专门的外层释放策略。注册能力位、方向、格式回调和 VB2 队列类型必须互相匹配。

## 11. 生命周期周边的几个辅助机制

`video_device` 还承载一些节点级辅助状态。它们也要放回前面的所有权和分发边界理解，不能因为字段出现在同一个结构体里，就认为注册函数会自动完成其功能。

### sysfs 属性仍然描述同一个节点对象

`video_class` 为视频节点提供 `name`、`index`、`dev_debug` 等属性。属性回调收到 `struct device *` 后，通过内嵌关系回到同一个 `video_device`，读取或更新节点成员。`dev_debug` 是控制核心调试输出的位图，不是每个节点重新分配一个设备身份。

### 优先级不是调度优先级

`v4l2_prio_state` 记录不同访问等级当前各有多少打开上下文。优先级辅助函数更新这些计数，并可在需要优先级检查的标准操作中比较当前句柄与最高活动级别；不满足时可能返回 `-EBUSY`。这不是 Linux 进程调度优先级，也不会自动检查所有驱动自定义操作。

### 锁字段不会自动保护所有回调

`video_device->lock` 是标准 ioctl 分发可使用的互斥锁指针。不要推断所有核心包装函数都会自动取得它：打开、read、mmap、poll 与 ioctl 的同步路径并不完全相同。使用 `video_ioctl2()` 的路径会按标准分发规则选择合适锁，队列类操作还可能使用 `vb2_queue->lock`；驱动的自定义路径仍需明确自己的锁顺序。

如果设备启用 Media Request，核心关闭路径会在需要时用 request 队列互斥锁序列化关闭/流取消与新 request 提交，避免两条路径意外交错。这把锁解决的是请求队列的特定并发问题，不能替代节点管理锁、队列锁或硬件退出同步。

### Media Controller 的 pipeline start 不是硬件开流

`video_device_pipeline_start()` / `video_device_pipeline_stop()` 把节点接入媒体管线状态管理，并按节点实体的 pad 条件调用 Media Controller 层。它们不等同于启动摄像头寄存器或 DMA；实际硬件流仍要由驱动和完整媒体管线按对应规则启动、停止。

## 12. 按层定位常见问题

```bash
# 节点文件、设备号与权限
ls -l /dev/video*
stat /dev/video0
cat /sys/class/video4linux/video0/dev
cat /sys/class/video4linux/video0/name

# 查看内核识别到的 V4L2 设备与能力（安装 v4l-utils）
v4l2-ctl --list-devices
v4l2-ctl --all -d /dev/video0

# 只有集成 Media Controller 的设备才适合检查媒体拓扑
media-ctl --print-topology
```

| 现象 | 排查方向 |
| --- | --- |
| 没有 `/dev/videoX` | 驱动是否完成 `video_register_device()`；设备模型是否发布；devtmpfs/udev 是否工作；检查 probe 日志和 sysfs |
| 节点序号与预期不同 | 看 `num`、minor 和同组 `index`，并核对 `CONFIG_VIDEO_FIXED_MINOR_RANGES`；不要把文件名后缀当 minor |
| `open()` 返回 `-ENODEV` | 节点可能尚未激活或已经注销/热拔出；检查注册标志对应的生命周期和驱动移除时序 |
| ioctl 返回 `-ENOTTY` | 检查节点 `unlocked_ioctl`、是否使用 `video_ioctl2()`、回调表/能力/方向和标准命令有效集合 |
| 注销后对象迟迟不释放 | 检查仍打开的文件及其引用；同时核对每条成功 open 是否最终归还引用 |
| 一关闭就崩溃或 double-free | 区分文件级 `fops->release` 和节点级 `vdev->release`；检查是否在成功注销后手动提前释放 |

## 13. 阅读源码时的检查清单

1. 先找到驱动中 `video_device` 的分配方式，确认 `release` 是否与独立/内嵌内存布局匹配。
2. 沿 `video_register_device()` 进入 v6.1 的 `__video_register_device()`，逐个标记编号、全局表、cdev、设备模型和 registered flag 的建立顺序。
3. 从 `v4l2_fops` 的 `.open` 跟到 `video_devdata()`，验证文件 inode 的 minor 如何回到 `video_devices[]`。
4. 分开检查 `video_device->fops` 和 `ioctl_ops`，确认标准 ioctl 辅助层是否真的接通。
5. 追踪 `video_unregister_device()`、核心 `v4l2_release()`、`video_put()` 和设备最终 `.release`，每次引用获取都找到配对归还点。
6. 最后回到驱动的 remove/disconnect 路径，确认硬件停机同步不是错误地寄希望于 V4L2 节点引用计数自动完成。

本文关注的主线可以压缩为一句话：注册建立身份和入口，核心包装层按设备号找到节点并转发操作，注销先关闭新访问，引用关系再决定何时清理入口和内存。弄清这几层，才有条件继续追踪格式协商、videobuf2 队列、媒体拓扑与实际采集硬件。

## 参考资料

本文参考飞一样的成长《V4L2 源码深度解析：从 video_device 到 /dev/videoX 的完整生命周期》（2026-09-23），并按 Linux v6.1 源码与内核文档重新核对、组织；未转载原文图表。

延伸阅读：[Buildroot 从零构建](https://yanruihe.github.io/posts/buildroot-from-zero/) · [Yocto 从零构建](https://yanruihe.github.io/posts/yocto-from-zero/) · [嵌入式 Linux 知识库](https://yanruihe.github.io/knowledge-base/)

- [Linux v6.1 `v4l2-dev.c` 源码](https://github.com/torvalds/linux/blob/v6.1/drivers/media/v4l2-core/v4l2-dev.c)
- [Linux v6.1 V4L2 video device 文档](https://docs.kernel.org/6.1/driver-api/media/v4l2-dev.html)
- [Linux v6.1 V4L2 device instance 文档](https://docs.kernel.org/6.1/driver-api/media/v4l2-device.html)
