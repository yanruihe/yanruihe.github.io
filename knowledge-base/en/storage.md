# eMMC, MTD, and Embedded Linux Filesystems

This topic separates three concepts that are often conflated: eMMC is a managed block device; MTD targets raw NAND/NOR flash; and ext4, F2FS, and UBIFS sit on different storage interfaces. Choose and debug a stack only after identifying whether the underlying device exposes block semantics or raw-flash semantics.

## 1. Two different storage stacks

```text
eMMC: SoC MMC host → MMC core/block → /dev/mmcblkN → partition → ext4 / F2FS
Raw NAND: NAND controller → MTD (/dev/mtdN) → UBI volume (/dev/ubiN_M) → UBIFS
```

eMMC contains a controller/FTL and Linux normally exposes its user area as a block device. It may also have special areas such as boot partitions and RPMB, each with different access policies. Do not treat eMMC as MTD. Raw NAND has erase blocks, bad blocks, and erase-cycle limits; it cannot be assumed to support block-device-style in-place overwrites. MTD exposes raw flash, UBI adds volume management and wear leveling, and UBIFS runs on a UBI volume.

MTD abstracts chip/controller differences into discoverable capacity, erase size, write granularity, and read/write/erase operations, and may expose OOB/ECC capabilities. Actual ECC placement/strength and bad-block policy still depend on the controller and board configuration. NAND is erased by erase block and programmed by page; bad-block handling, ECC, and OOB layout must use the same convention as the production flashing tool. `/dev/mtdN`, an MTD partition, `mtdblock`, and a UBI volume are different layers. Seeing a device node does not mean it is safe to format it like a generic block device.

## 2. eMMC bring-up and read-only diagnostics

Check power, power-up sequencing, bus width, CMD/CLK/DAT signal integrity, reset, device-tree pinctrl, and bus frequency. Then inspect controller logs and the block device:

```sh
dmesg | grep -Ei 'mmc|sdhci|mmcblk|timeout|crc|tuning'
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
cat /sys/kernel/debug/mmc*/ios 2>/dev/null
mmc extcsd read /dev/mmcblk0
```

`mmc extcsd read` reads and decodes EXT_CSD; first confirm that the device node identifies the target eMMC. Look for initialization/enumeration failures, CRC/timeouts, mode switching and tuning, retries, temperature/voltage conditions, boot-partition setup, and power-loss recovery. For HS200/HS400 issues, return to host/device capabilities, routing, sampling phase/tuning, and electrical measurements; do not mask a marginal timing path merely by reducing clock speed.

For protocol analysis, treat an operation as a transaction made of CMD/response, DAT transfer, and busy state. The host initializes the card and negotiates operating voltage/capabilities, reads card identity and selects it, queries EXT_CSD, then switches to a bus width and timing mode supported by both sides. Reads/writes also require checking data CRC, response status, and completion of the write-busy phase. Exact stages and high-speed tuning sequences vary with specification revision, device capability, and host implementation; use the applicable eMMC specification, device data sheet, and MMC-host logs rather than treating one board's waveform settings as universal.

`mmc-utils` also supports write protection, cache, partition attributes, sanitize, RPMB, and other operations. Many change device state or are irreversible. Never copy write commands onto production media; read the tool and device documentation and validate on a disposable test device with a recovery plan.

## 3. Boundaries between ext4, F2FS, and UBIFS

| Filesystem | Underlying interface | Key idea | Common context |
| --- | --- | --- | --- |
| ext4 | Block device | Block groups, extents, journaling, and other mechanisms; journaling helps recover metadata consistency after a crash | General block storage such as eMMC/SSD; mature ecosystem |
| F2FS | Block device | Log-structured design for flash-based block devices, with checkpoints and segment cleaning | Workloads where write pattern, performance, recovery, and tooling need evaluation |
| UBIFS | UBI volume (above MTD) | Designed for raw flash; UBI abstracts bad blocks and wear management while the filesystem maintains indexes/logs | Raw MTD flash such as NAND |

F2FS does not bypass the eMMC's internal FTL; it is a filesystem on a block device, while the eMMC controller still manages the flash. UBIFS cannot be mounted directly on a normal eMMC partition. A common NAND stack is MTD → UBI → UBIFS; raw MTD and UBI-volume tools/formatting are not interchangeable.

## 4. Layered filesystem troubleshooting

Start with read-only collection of device, partition, mount, and kernel-error information:

```sh
findmnt
blkid
dmesg | grep -Ei 'mmc|I/O error|ext4|f2fs|ubi|ubifs|mtd'
cat /proc/mtd
ubinfo -a
mtdinfo
```

1. If a device disappears or reports I/O timeouts, investigate power, controller, signal integrity, power management, and media state first; filesystem errors may be downstream symptoms.
2. If a block device is healthy but mounting fails, verify partition/filesystem type, kernel configuration, image/tool versions, and superblock or unsupported-feature messages.
3. If raw NAND/UBI attach fails, check MTD partition boundaries, erase-block size, ECC/OOB configuration, bad blocks, and UBI parameters against the controller and flashed image.
4. Only after a backup and target-media check should offline filesystem checking or repair be considered. Never run format, erase, or repair tools against a mounted root filesystem.

## 5. Reliability validation and an incident example

For a power-loss/reboot campaign, use a dedicated test board and recoverable image. Record workload, free space, sync policy, interruption point, boot time, file checksums, I/O errors, and bad-block/wear indicators. Cover many small files, sequential writes, near-full conditions, repeated reboot, and temperature changes. Reproduce in a virtual device or test partition before testing real media; every destructive test needs an explicit data-loss boundary and recovery procedure.

Example: the root filesystem occasionally mounts read-only. Do not immediately run `fsck` or reflash. Save the serial log and check whether eMMC timeout/CRC errors precede the ext4/F2FS report. Investigate power dips, reset, cache flush, and write load; copy data offline before examining media and filesystem state. A different filesystem may not fix an underlying I/O fault.

## Official references

- [Linux MMC/SD/SDIO support](https://docs.kernel.org/driver-api/mmc/index.html)
- [MMC tools and mmc-utils](https://docs.kernel.org/driver-api/mmc/mmc-tools.html)
- [Linux MTD documentation](https://docs.kernel.org/driver-api/mtd/index.html)
- [ext4 design](https://docs.kernel.org/filesystems/ext4/)
- [F2FS design](https://docs.kernel.org/filesystems/f2fs.html)
- [UBIFS and UBI](https://docs.kernel.org/filesystems/ubifs.html)
