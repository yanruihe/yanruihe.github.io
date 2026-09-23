# Linux Kernel Memory Management and Crash Analysis

The goal is not to memorize APIs. It is to build a path from symptoms and preserved evidence to object lifetime, concurrency, memory source, and hardware transactions. A driver panic often exposes an earlier out-of-bounds access, use-after-free, bad DMA address, or race only later.

> **Platform/source baseline:** Rockchip RK3588 and the `develop-6.1` branch of the official [`rockchip-linux/kernel`](https://github.com/rockchip-linux/kernel/tree/develop-6.1) repository. The source snapshot checked for this guide is `77168c8d5ab82399f65a80e9f807b50ba37cf483`. Analysis requires the exact source commit, `.config`, DTS, `vmlinux`, and module symbols for the image under investigation. Reserved memory, CMA, IOMMU, peripheral DMA capabilities, and detector options depend on the board configuration.

## RK3588 + Rockchip 6.1 debugging baseline

- Start with the matching board DTS and `.config` to confirm `reserved-memory`, CMA, IOMMU/DMA mask, console, and actual pstore/ramoops or kdump setup. Do not copy one RK3588 development board's memory layout to another.
- Symbolize an Oops/vmcore with the exact `develop-6.1` commit and its unstripped `vmlinux`, modules, `System.map`, and build ID. A matching branch name does not make build artifacts interchangeable.
- Availability of KASAN, KFENCE, KCSAN, lockdep, and kdump depends on the branch, kernel configuration, boot chain, and available memory. Validate overhead and support on the corresponding RK3588 test image before choosing product settings.

## 1. Memory and lifetime concepts in drivers

- **Page allocator / slab**: page-sized allocations and caches of common smaller objects serve different sizes. `kmalloc`/`kzalloc` are commonly used for small physically contiguous kernel objects; `vmalloc` provides virtually contiguous memory backed by potentially non-contiguous physical pages. A CPU virtual address is not automatically a device DMA address.
- **DMA API**: obtain DMA addresses according to the device DMA mask and mapping direction; distinguish coherent and streaming mappings and follow map/unmap/sync lifetimes. Do not use `virt_to_phys()` as a general DMA mapping method.
- **Allocation context**: `GFP_KERNEL` may sleep. Interrupt/atomic contexts cannot use allocation paths that may block. Check lock ownership, calling context, and failure rollback.
- **Ownership**: refcounts, completions, workqueues, timers, IRQs, and DMA callbacks can extend object lifetime. Remove/error paths must stop new requests, synchronize asynchronous users, release IRQ/DMA resources, and only then free the object.
- **Concurrency and locks**: define who protects each field, lock ordering, and IRQ-context rules. Locking a pointer does not keep its object alive after an asynchronous callback exits.

When reading code, draw resource pairs: `alloc ↔ free`, `map ↔ unmap`, `request_irq ↔ free_irq`, `submit ↔ complete/cancel`. Trace every error exit, deferred probe, remove, suspend, and resume through the state machine.

## 2. Preserve crash evidence before interpreting it

Before chasing an intermittent failure, confirm that serial/console logs and exact matching symbols are available. Release artifacts should preserve kernel configuration, source commit, unstripped `vmlinux`, `System.map`, module symbols, and build ID. Addresses and line numbers are trustworthy only when versions match exactly. When enabling pstore/ramoops or kdump, verify the boot chain, reserved memory, and storage path—not just that a config option is enabled.

```text
Incident: full Oops/Panic, time, workload, temperature, trigger, peripheral state
Artifacts: exact vmlinux, modules, System.map, .config, source commit/build ID
Analysis: exception → PC/LR/registers → stack → first suspicious driver frame → lifetime/concurrency/DMA
Validation: minimal reproduction → diagnostics/detectors → fix → original case and regression stress
```

For `BUG: unable to handle...`, `Oops`, or `panic`, first classify NULL/invalid address, permission fault, stack/overflow, deadlock, or hardware exception. Read the fault address, access direction, PC/LR, registers, and complete stack; correlate them with disassembly and the matching source. Then determine whether the top frame is only the victim, tracing the pointer's origin, last writer, asynchronous callback, and device timing.

If a vmcore is available, use `crash` with the exact matching `vmlinux` to inspect tasks, stacks, modules, and memory. With only serial logs, retain the complete raw output instead of just the last few lines. Label unsupported conclusions as hypotheses and design experiments that could falsify them.

## 3. Detectors and diagnostic configurations

Choose tools in a development/test kernel according to the suspected class: KASAN detects out-of-bounds and use-after-free; KFENCE samples for memory errors at lower overhead; KCSAN finds some data races; lockdep checks lock dependencies; kmemleak helps identify possible leaks; UBSAN catches some undefined behavior. Instrumentation changes timing and resource usage, so a race may behave differently. Keep both an uninstrumented baseline and a detector build.

Products should also have a crash-evidence strategy: serial/network console, pstore/ramoops, persistent logs, or kdump vmcore. Evaluate capacity, reserved memory, media wear, sensitive data, and reset policy. Do not enable automatic panic or intentionally trigger crashes on user devices merely to make a failure easier to reproduce.

## 4. Low-speed buses: software logs plus electrical evidence

### I2C

Check address convention (7-bit vs 10-bit), START/STOP, repeated START, ACK/NACK, pull-ups, rise time, bus frequency, arbitration/clock stretching, and device power-up timing. On Linux, distinguish adapter/controller errors, transfer errno, and chip-register responses. `i2cdetect` sends probe transactions to addresses; some devices should not be probed. Check the schematic and data sheet before scanning an active bus.

### SPI

Verify CPOL/CPHA, chip-select polarity, word length, maximum frequency, transfer direction, and transaction boundaries. Inspect CS/SCLK/MOSI/MISO with a logic analyzer. A successful controller transfer return does not prove that the device's sampling edge, register address, or timing requirements were met.

### UART

Check baud rate, data/parity/stop bits, TTL versus RS-232/RS-485 transceiver levels, TX/RX crossover, flow control, and interrupt/FIFO overruns. For garbled output, use a known USB-UART configuration and scope/logic analyzer to verify bit width and voltage before debugging clocks and pinmux; logs themselves can lose bytes to FIFO overrun.

## 5. Analysis exercise: intermittent I2C-driver panic

1. Fix the board, firmware, bus speed, workload, temperature, and trigger rate; determine whether the fault consistently occurs at the same access.
2. Preserve the full panic and build artifacts. Map symbols with `addr2line`/`crash` against the exact build; check whether the fault address came from a freed device object or an empty transfer buffer.
3. Trace probe, IRQ, workqueue, remove, and error cleanup. Check whether the state object is freed before work/timer/IRQ cancellation completes, or whether code sleeps in a lock/atomic context.
4. Use KASAN/KFENCE/lockdep and bus waveforms to test lifetime, lock-order, and device-timing hypotheses; change one variable at a time.
5. After the fix, cover probe failure, hot removal (if supported), repeated suspend/resume, bus-error injection, and long stress runs; confirm there are no new leaks or warnings.

## 6. Postmortem template

Keep the symptom and reproduction rate, raw crash log, hardware/software versions, matching symbols, suspected lifetime diagram, hypotheses ruled out, detector and measurement results, root-cause evidence, fix diff, regression tests, and remaining risk. Separate “what happened” from “why it happened”; the latter must be supported by evidence.

## Official source and documentation (Rockchip Linux 6.1)

- [Rockchip kernel `develop-6.1` branch](https://github.com/rockchip-linux/kernel/tree/develop-6.1)
- [RK3588 common device tree](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588.dtsi) · [RK3588S device tree](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/boot/dts/rockchip/rk3588s.dtsi)
- [Kdump documentation in this branch](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/admin-guide/kdump/kdump.rst) · [KASAN](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/dev-tools/kasan.rst) · [KFENCE](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/dev-tools/kfence.rst)
- [I2C driver documentation](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/driver-api/i2c.rst) · [SPI driver documentation](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/driver-api/spi.rst) · [Serial driver documentation](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/driver-api/serial/driver.rst)
