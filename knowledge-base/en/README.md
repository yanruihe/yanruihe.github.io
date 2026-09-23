# Knowledge Base

This is a searchable knowledge base for embedded Linux development. It connects general engineering practice, Git collaboration, and Yocto builds.

## Topics

| Topic | What it covers |
| --- | --- |
| Git | Change tracking, collaboration, recovery, and publishing |
| Yocto | Layers, recipes, images, devtool, and build debugging |

From-zero build series: [Buildroot 2025.02.18](../../posts/en/buildroot-from-zero/) · [Yocto 6.0.2](../../posts/en/yocto-from-zero/).

## Record format

1. **Context**: goal, platform, version, and constraints.
2. **Operation**: reusable commands or configuration.
3. **Verification**: logs, tests, or artifacts that prove the result.
4. **Risk**: version differences, destructive actions, and rollback.
5. **References**: official documentation, commits, and related issues.

Recommended loop: `Capture → Minimal reproduction → Verification → Git commit → Site publication`.
