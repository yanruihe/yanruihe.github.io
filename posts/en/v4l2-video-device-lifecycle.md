# V4L2 Internals: The Lifecycle from `video_device` to `/dev/videoX`

Starting with an application's `open("/dev/video0")`, this article follows how the Linux 6.1 V4L2 core assigns node numbers, registers a character device, dispatches file operations, and waits for the last reference before reclaiming an unregistered object. The main source is `drivers/media/v4l2-core/v4l2-dev.c`. Image-format negotiation, videobuf2 queues, and sensor drivers are covered only where their boundaries matter.

## 1. Follow one open from userspace

Userspace sees a pathname. The kernel follows the character-device number to a V4L2 node, then the core wrapper calls the driver callbacks:

```text
open("/dev/video0")
  → pathname lookup yields a character-device inode and dev_t
  → dev_t resolves to a cdev
  → cdev->ops points to the V4L2 core v4l2_fops
  → v4l2_open() looks up video_device by minor
  → video_get() keeps the node object alive
  → video_device->fops->open()
  → core wrappers dispatch later read / ioctl / mmap / poll operations
```

`v4l2-dev.c` manages how a node appears, is accessed, and is removed. It is not the camera capture engine. Setting a streaming capability does not create buffers, and the V4L2 core does not stop a driver's DMA, interrupts, or sensor for it.

## 2. Separate the node, its parent, and one open file

`struct video_device` represents one node instance that exposes a V4L2 file interface. A physical device can provide capture, output, or codec nodes. They may share one `struct v4l2_device`, while retaining their own node numbers, capabilities, and operation tables.

| Object | Lifetime and responsibility | Do not confuse it with |
| --- | --- | --- |
| `struct v4l2_device` | Organizes V4L2 nodes, subdevices, and shared state | The `/dev/videoX` node |
| `struct video_device` | Core object for one V4L2 character-device node | The whole camera or one open context |
| Embedded `struct device` | Device-model identity, sysfs hierarchy, and object references | The character-device operation entry point |
| `struct cdev` | Connects a character-device number to `file_operations` | Device-model naming and full release policy |
| `struct file` / `file->private_data` | File object and driver context for an open | The shared `video_device` |
| `struct v4l2_fh` | Optional standard V4L2 file-handle and event association | An object created unless the driver uses the helper API |
| `struct vb2_queue` | Video-buffer queue associated with the node | A pointer that proves a queue is initialized or streaming |

When reading the structure, ask who creates each pointer, who owns it, and who releases it. Storing a pointer in `video_device` neither copies the target object nor transfers ownership of its memory.

### `fops` and `ioctl_ops` have different jobs

`video_device->fops` is the node's file-operation table, with entry points such as `open`, `release`, `read`, `poll`, `mmap`, and `unlocked_ioctl`. `video_device->ioctl_ops` is the table of standard V4L2 ioctl callbacks, such as `vidioc_querycap`, `vidioc_s_fmt_vid_cap`, `vidioc_reqbufs`, and `vidioc_streamon`.

A common standard-dispatch path looks like this:

```text
userspace ioctl(fd, VIDIOC_..., arg)
  → core v4l2_ioctl()
  → node fops->unlocked_ioctl()
  → driver commonly wires this to video_ioctl2()
  → dispatch by command, arguments, and format type to ioctl_ops->vidioc_*()
```

Wiring `unlocked_ioctl` to `video_ioctl2` is a common driver choice; it does not happen merely because `ioctl_ops` is populated. A custom ioctl dispatcher can follow another route, so do not assume that it uses the standard callback table, valid-command bitmap, or standard locking.

## 3. The `8` in `/dev/video8` is not necessarily minor 8

Several `video_device` fields look like variations of the same identity:

| Field | Meaning | Main use |
| --- | --- | --- |
| `name` | Descriptive name supplied by the driver | Description in sysfs and media entities |
| `num` | Suffix in the device-node name | Creates a device-model name such as `video8` |
| `minor` | Character-device minor number | `cdev_add()` and `video_devices[]` lookup |
| `index` | Node index within one `v4l2_device` | Distinguishes nodes in the same group |

The `8` in `/dev/video8` belongs to the node-naming namespace; it is not parsed from the pathname and passed to the driver. The core reads the minor from the inode's `dev_t`, then looks up the node. Without fixed minor ranges, `num` and `minor` can be allocated independently; with `CONFIG_VIDEO_FIXED_MINOR_RANGES`, the mapping differs. During debugging, use the device number from `stat` and the sysfs `dev` attribute instead of guessing from the filename.

`vfl_type`, `vfl_dir`, and `device_caps` are also separate dimensions. The type distinguishes video, radio, VBI, and other node classes; direction describes receive, transmit, or memory-to-memory operation; capabilities declare the V4L2 functions exposed by the node. A capability bit does not implement the corresponding callback.

## 4. Core initialization does not create every video node

V4L2 core initialization registers a character-device number range and the `video4linux` device class. This prepares shared infrastructure; it does not create `/dev/video0` for every camera. A driver later prepares one `video_device` per node and calls `video_register_device()`.

The appearance of a device file in `/dev` also involves the Linux device model and a device-node manager such as devtmpfs or udev. Keep these operations distinct: `cdev_add()` maps a device number to file operations; `device_register()` publishes a device-model object; node-management mechanisms make the character-device file visible in `/dev`.

## 5. Registration publishes the node in stages

Drivers commonly call:

```c
ret = video_register_device(vdev, VFL_TYPE_VIDEO, -1);
```

In Linux 6.1 this public helper enters `__video_register_device()`. Following resources as they are established makes concurrency and failure cases easier to reason about than memorizing a list of function names:

1. **Validate the contract and prepare defaults**: a release callback, parent `v4l2_device`, and capabilities for non-subdevice nodes must be valid; the file-operation table and required callbacks must already be set. The core initializes `fh_lock`/`fh_list`, selects the node type, and inherits the parent device, control handler, and priority state when those fields are unset.
2. **Reserve a name and device number**: under `videodev_lock`, the core selects `num`, `minor`, and the group's `index`, marks the number bitmap, and stores the pointer in `video_devices[minor]`. Once this lock is released the slot is reserved, but V4L2 file operations are not yet enabled.
3. **Compute valid standard ioctls**: if `ioctl_ops` is used, the core builds a candidate set from node type, direction, capabilities, and callbacks. `v4l2_disable_ioctl()` must be called before registration; in this registration path, pre-set bits mean “disable”, while the resulting bitmap represents supported standard commands.
4. **Establish the character-device entry**: allocate a `cdev`, attach the common core `v4l2_fops`, set the module owner, and call `cdev_add()` for the major/minor. All nodes enter the same core wrappers first, which then dispatch to each node's `vdev->fops`.
5. **Publish the device-model object**: fill in the class, `dev_t`, parent, and name, then call `device_register()`. This creates the device-model/sysfs representation and enters the system device-node path; it is not a V4L2-specific replacement for calling `mknod()`.
6. **Hold the parent and establish optional media associations**: the node holds a reference to its parent `v4l2_device`; when Media Controller support is enabled, the node can also be connected to the media topology. A media interface object is not the same thing as the `/dev/videoX` character-device file.
7. **Enable access last**: set `V4L2_FL_REGISTERED`, release the management lock, and return success. The open path checks this state, so an assigned number, a non-null global-table entry, or a successful `cdev_add()` alone does not mean the node is active.

```text
initial object → reserve numbers → compute ioctl set → cdev mapping → device/sysfs publish
               → parent/media association → set REGISTERED → allow new opens
```

Initialize every object, back-pointer, and lock that callbacks may read before registration. After publication, another CPU can enter `open()` immediately, even before the registering caller executes its next statement.

### An example of `num`, `minor`, and `index`

Assume a build without fixed minor ranges. A node may receive the name suffix `video8` while the first free slot in the global character-device table is minor `0`; a node of another class may then occupy minor `1`. The `index` within one `v4l2_device` is allocated independently from the first free slot. This illustrates that the numbers answer different questions; it does not promise the same values under every configuration.

`index` is not just a monotonically increasing counter either. The core scans existing nodes associated with the same `v4l2_device` and picks the first free index, so an index can be reused after its previous node is finally released.

### Failure cleanup and object ownership

Failure paths undo only resources that have already been acquired. If registration fails after reserving a number, the core removes any established `cdev`, global-table entry, and number reservation. But `video_register_device()` does not call `vdev->release` on failure. The driver must release its node according to its allocation layout: a standalone object from `video_device_alloc()` is usually released with `video_device_release()` in the failure path; an embedded object follows the outer object's lifetime policy.

Do not treat a failed object as a successfully registered node and continue with normal unregister, or edit a few fields and blindly retry registration. The kernel API documentation explicitly leaves object cleanup after registration failure to the caller.

## 6. The open path: lookup, validation, and refcounting share one critical section

During registration, the core stores:

```c
video_devices[vdev->minor] = vdev;
```

At open time, `video_devdata(file)` uses the inode minor to look up the same table. The core's essential sequence can be summarized as:

```c
mutex_lock(&videodev_lock);
vdev = video_devdata(filp);
if (!vdev || !video_is_registered(vdev)) {
        mutex_unlock(&videodev_lock);
        return -ENODEV;
}
video_get(vdev);
mutex_unlock(&videodev_lock);

/* Do not run a complex driver open callback under the global node lock. */
if (vdev->fops->open)
        ret = vdev->fops->open(filp);
if (ret)
        video_put(vdev);
```

The locked sequence “lookup → confirm registered → acquire an object reference” is one handoff. If the core looked up a pointer, unlocked, and only later took a reference, an unregistering thread could complete final release first, leaving open with a dangling pointer. The core drops the global lock before calling the driver so a complex or sleeping `open()` does not block management of every other node.

Locks and references have different jobs: the lock protects the state handoff, while the reference keeps the object alive. The core's second registered-state check does not make driver callbacks and hardware removal fully mutually exclusive; the driver must still synchronize disconnect, stream shutdown, and in-flight operations.

Do not mix these three ways of obtaining data:

- `video_devdata(file)`: the `video_device` for the current file.
- `video_get_drvdata(vdev)` / `video_drvdata(file)`: driver-private data associated with the node.
- `file->private_data`: usually the context created for this particular `open()`; independent opens normally need independent contexts.

The core does not populate `file->private_data` for the driver or clean up private allocations made by a driver `open()` that fails.

## 7. What the file-operation wrappers do and do not do

After a successful open, the core wrappers are installed in the file-operation path. Later `read()` and `ioctl()` calls do not repeat character-device open lookup; the core checks node state and callback presence, then forwards the call.

| Operation | Main responsibility of the core | Typical boundary |
| --- | --- | --- |
| `read` / `write` | Check callback and registration state, then forward | Does not guarantee a complete frame copy or wait for a frame automatically |
| `mmap` | Check callback and node state, then invoke the driver | Does not allocate buffers; actual mapping is often handled by driver/VB2 |
| `unlocked_ioctl` | Forward to the node's file-operation table | Standard commands often continue through `video_ioctl2()` and `ioctl_ops` |
| `poll` | Forward event waiting or return the appropriate default/error mask | Does not infer “a frame is ready” merely from a non-null `queue` pointer |
| `release` | Call the driver's close handler, then drop the core open reference | Old files still need close cleanup after the node is unregistered |

When an ioctl returns `-ENOTTY`, trace the file-level ioctl callback, standard `video_ioctl2()` dispatch, `valid_ioctls` filtering, and the specific `vidioc_*` implementation. The final errno alone does not identify which layer rejected the command. `valid_ioctls` is not a generic authorization table for arbitrary private ioctls either.

## 8. Unregistering blocks new access; it does not immediately free memory

Remove a registered node with `video_unregister_device(vdev)`, not by directly removing the internal cdev or clearing the core's global table by hand. The main Linux 6.1 sequence is:

1. Clear `V4L2_FL_REGISTERED` under `videodev_lock`, so a later normal open cannot acquire a new node reference.
2. Wake waiters using the standard `v4l2_fh` event mechanism so they can re-check device state.
3. Call `device_unregister()` to remove the device-model object and drop the registration reference.

Files that were already open may still exist and must go through their own `release()` cleanup. When `device_unregister()` returns, `vdev` may already have been finally released, or it may remain alive due to old file references. The caller cannot tell whether it is still valid merely because the function just returned. The kernel documentation likewise states that no new opens are accepted after unregister; old file operations other than release return errors, and the final node release callback runs when the last user exits.

Unregister does not mean that the driver hardware has safely stopped. Stopping DMA, synchronizing or masking interrupts, waking private wait queues, preventing new queue submissions, and handling hot unplug remain the responsibility of the driver and relevant frameworks. `V4L2_FL_REGISTERED` is node-access state, not a hardware-health or streaming-state flag.

## 9. Several release paths and references have different jobs

At least these paths must be distinguished:

| Callback/operation | Object affected | When it runs |
| --- | --- | --- |
| `vdev->fops->release(file)` | Driver context for one open | When the file object finally closes; can happen multiple times |
| Core `v4l2_release()` / `video_put(vdev)` | Drops the node reference held by a successful open | After driver release, even if that callback returns an error |
| `v4l2_device_release(struct device *)` | V4L2 core registration resources | When references to the node's `struct device` reach zero |
| `vdev->release(vdev)` | Node and driver-private storage | Final release after core cleanup |
| `v4l2_device_put()` | Parent V4L2 organization object | Returned by final node-release logic according to its lifetime contract |

In a simplified example with only a registration reference and two successful opens, the reference count is illustrated as 1 after registration, 2 after file A opens, and 3 after file B opens. Unregister drops the registration reference to 2; final release of A and B drops their references, after which the count may reach 0. Real counts can also include device-model and temporary references; this is a pairing illustration, not a fixed count formula in the code.

The core's final callback recovers `video_device` from the embedded `struct device`, then clears `video_devices[minor]`, the `cdev`, the number reservation, and applicable media associations before calling the driver's `vdev->release`. The number must stay reserved until final release: if the old minor were reused immediately at unregister, an old file could later close using its inode minor and find the wrong new node in the table.

### Why there is more than one `release`

- `fops->release` means “this open is finished”; it cleans each file context.
- `vdev->release` means “the node object is finished”; it may free `video_device` or its enclosing object.
- The `struct device` `.release` is first handled by the V4L2 core to remove core-owned registration state.

Use `video_device_release` for a standalone allocation. Static or embedded objects need a callback suited to their layout. After a successful unregister, do not unconditionally call `video_device_release(vdev)` yourself; that can race remaining file references and cause use-after-free or double-free.

## 10. Example: organizing registration of one node

This only shows how a node connects to the framework; it is not a complete compilable camera driver. `ctx`, the queue, locks, operation tables, and hardware setup belong to the driver. `ctx` and callback tables must remain valid as long as the node may be used.

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

        /* Prepare reverse pointers before callbacks can observe the node. */
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

On successful removal, the driver first coordinates hardware shutdown and in-flight operations, then calls `video_unregister_device(ctx->vdev)`. Let references and `vdev->release` govern final storage release. If `ctx` cannot outlive every still-open node file, add a parent reference or a dedicated outer-object release policy. Capability bits, direction, format callbacks, and VB2 queue type must agree.

## 11. Auxiliary mechanisms around the lifecycle

`video_device` also carries node-level supporting state. Read these fields in the context of the ownership and dispatch boundaries above; a field being present in the same structure does not mean registration implements its behavior automatically.

### Sysfs attributes still describe the same node

`video_class` provides attributes such as `name`, `index`, and `dev_debug`. An attribute callback receives `struct device *` and follows the embedded-object relationship back to the same `video_device` to read or update a member. `dev_debug` is a bitmap controlling core debug output, not a second device identity for each node.

### V4L2 priority is not scheduler priority

`v4l2_prio_state` tracks how many open contexts are active at each access priority. The priority helpers update these counts and can compare a file handle with the highest active level for standard operations that request such a check; a lower-priority operation may receive `-EBUSY`. This is not Linux process scheduling priority, and it does not automatically check every driver-specific operation.

### A lock field does not protect every callback automatically

`video_device->lock` is a mutex pointer that standard ioctl dispatch can use. Do not infer that every core wrapper acquires it: open, read, mmap, poll, and ioctl do not have identical synchronization paths. The `video_ioctl2()` path selects a lock according to standard dispatch rules, and queue operations may use `vb2_queue->lock`; a custom driver path still needs an explicit locking order.

When Media Request is enabled, the core close path can use the request-queue mutex to serialize close/stream cancellation against new request submission. This addresses a specific request-queue race; it does not replace node-management locks, queue locks, or hardware-removal synchronization.

### Media Controller pipeline start is not hardware stream-on

`video_device_pipeline_start()` / `video_device_pipeline_stop()` connect the node to Media Controller pipeline-state management and use the media layer subject to the node entity's pad requirements. They do not start camera registers or DMA by themselves; the driver and complete media pipeline still need to start and stop the actual hardware stream.

## 12. Debug common failures one layer at a time

```bash
# Node file, device number, and permissions
ls -l /dev/video*
stat /dev/video0
cat /sys/class/video4linux/video0/dev
cat /sys/class/video4linux/video0/name

# Devices and capabilities recognized by the kernel (install v4l-utils)
v4l2-ctl --list-devices
v4l2-ctl --all -d /dev/video0

# Inspect topology only for devices integrated with Media Controller
media-ctl --print-topology
```

| Symptom | Where to look |
| --- | --- |
| No `/dev/videoX` | Did the driver finish `video_register_device()`? Was the device model published? Are devtmpfs/udev working? Check probe logs and sysfs. |
| Unexpected node number | Check `num`, `minor`, and group `index`, and `CONFIG_VIDEO_FIXED_MINOR_RANGES`; do not treat the filename suffix as minor. |
| `open()` returns `-ENODEV` | The node may not be active or may have been unregistered/hot-unplugged; inspect the registration lifetime and driver-removal ordering. |
| ioctl returns `-ENOTTY` | Check node `unlocked_ioctl`, use of `video_ioctl2()`, callback table, capabilities, direction, and standard-command filtering. |
| Object remains after unregister | Check for open files and their references; verify every successful open eventually drops its reference. |
| Crash or double-free at close | Distinguish file-level `fops->release` from node-level `vdev->release`; check for manual free after successful unregister. |

## 13. A source-reading checklist

1. Find how the driver allocates `video_device` and whether `release` matches the standalone or embedded-memory layout.
2. Follow `video_register_device()` into Linux 6.1 `__video_register_device()` and mark when numbers, the global table, cdev, device model, and registered flag are established.
3. Start from `.open` in `v4l2_fops` and follow `video_devdata()` to see how the inode minor returns to `video_devices[]`.
4. Inspect `video_device->fops` and `ioctl_ops` separately; verify that the standard ioctl helper is actually connected.
5. Trace `video_unregister_device()`, core `v4l2_release()`, `video_put()`, and the device's final `.release`; pair each reference acquisition with a corresponding release.
6. Return to the driver's remove/disconnect path and make sure hardware shutdown is not mistakenly expected to happen automatically through the V4L2 node reference count.

The lifecycle can be summarized in one sentence: registration establishes node identity and entry points; core wrappers find and dispatch to the node; unregister blocks new access; references determine when registrations and memory can finally be removed. Understanding these layers gives a firm starting point for format negotiation, videobuf2 queues, media topology, and actual capture hardware.

## References

This article draws on the analysis published by 飞一样的成长, “V4L2 Source Deep Dive: The Full Lifecycle from `video_device` to `/dev/videoX`” (2026-09-23). It has been reorganized and checked against Linux 6.1 source and documentation; the original figures are not reproduced.

Related reading: [Buildroot from scratch](https://yanruihe.github.io/posts/en/buildroot-from-zero/) · [Yocto from scratch](https://yanruihe.github.io/posts/en/yocto-from-zero/) · [Embedded Linux knowledge base](https://yanruihe.github.io/knowledge-base/en/)

- [Linux v6.1 `v4l2-dev.c` source](https://github.com/torvalds/linux/blob/v6.1/drivers/media/v4l2-core/v4l2-dev.c)
- [Linux v6.1 V4L2 video-device documentation](https://docs.kernel.org/6.1/driver-api/media/v4l2-dev.html)
- [Linux v6.1 V4L2 device-instance documentation](https://docs.kernel.org/6.1/driver-api/media/v4l2-device.html)
