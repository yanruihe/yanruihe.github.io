# Knowledge Base

This searchable embedded Linux knowledge base covers Git/Yocto workflows, board-level networking/audio/storage bring-up, and kernel memory/crash diagnosis.

## Topics

| Topic | What it covers |
| --- | --- |
| Git | Change tracking, collaboration, recovery, and publishing |
| Yocto | Layers, recipes, images, devtool, and build debugging |
| Ethernet PHY and Wi-Fi | RGMII/SGMII, wireless-driver layers, and automotive Ethernet debugging |
| ALSA, ASoC, and CODECs | PCM/I2S paths, DAPM, audio quality, pops, and AEC |
| eMMC, MTD, and filesystems | Block/raw-flash boundaries; ext4, F2FS, and UBI/UBIFS |
| Kernel memory and crash analysis | Memory/DMA lifetime, panic evidence, and low-speed bus debugging |

From-zero build series: [Buildroot 2025.02.18](../../posts/en/buildroot-from-zero/) · [Yocto 6.0.2](../../posts/en/yocto-from-zero/).

## Record format

1. **Context**: goal, platform, version, and constraints.
2. **Operation**: reusable commands or configuration.
3. **Verification**: logs, tests, or artifacts that prove the result.
4. **Risk**: version differences, destructive actions, and rollback.
5. **References**: official documentation, commits, and related issues.

Recommended loop: `Capture → Minimal reproduction → Verification → Git commit → Site publication`.
