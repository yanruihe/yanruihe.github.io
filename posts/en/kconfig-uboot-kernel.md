# Kconfig in U-Boot and the Linux Kernel: From Options to Build Outputs

Both U-Boot and the Linux kernel use Kconfig to describe optional features, platform constraints, and dependencies. The useful skill is not memorizing menu paths; it is tracing a symbol from its definition and visibility through value resolution, `.config`, generated headers, and the final object files. Examples below use Rockchip U-Boot and Linux 6.1 for RK3588.

> **Source baseline:** Linux uses the current default branch, `develop-6.1`, of [`rockchip-linux/kernel`](https://github.com/rockchip-linux/kernel), checked at `77168c8d5ab82399f65a80e9f807b50ba37cf483`. U-Boot uses the current default branch, `next-dev`, of [`rockchip-linux/u-boot`](https://github.com/rockchip-linux/u-boot), checked at `1c535d65b8509f388d09e49fb6961f49fda35a1d`. Both branches can move; record the actual commit when reproducing or releasing a build.

## 1. How a configuration reaches firmware

```text
Kconfig files define symbols, types, dependencies, defaults, and menus
        ↓
defconfig provides a product/board starting point
        ↓  menuconfig / olddefconfig / savedefconfig
.config stores the resolved selection
        ↓  Kconfig generates Make-readable settings and headers
Makefiles use CONFIG_* to choose directories, objects, and rules
        ↓
U-Boot / Image / modules and other build outputs
```

Kconfig does not compile C files or determine whether hardware is physically wired. It computes which features are allowed in this build, then passes the result to Kbuild, U-Boot makefiles, and the C preprocessor. Finding a `CONFIG_*` name in source does not mean it is `y` in the current `.config`; writing it into `.config` does not bypass Kconfig dependencies either.

## 2. Symbol types and values

| Type | Typical use | Values/examples |
| --- | --- | --- |
| `bool` | A feature that is on or off | `y` / `n` |
| `tristate` | A kernel feature built in, as a module, or disabled | `y` / `m` / `n` |
| `string` | Paths, names, and string parameters | `"ttyS0"` |
| `int`, `hex` | Numeric values, addresses, or masks | `115200`, `0x...` |

For a Linux `tristate`, `y` builds into the kernel, `m` builds a module, and `n` omits the feature; `m` is available only when module support and dependencies permit it. The generated C macros differ too: built-in code generally sees `CONFIG_FOO`, while a module is represented by `CONFIG_FOO_MODULE`. In C, use kernel helpers such as `IS_ENABLED()` or `IS_REACHABLE()` where appropriate; do not assume `#ifdef CONFIG_FOO` treats `m` and `y` as equivalent.

Linux uses `tristate` widely to distinguish built-in code from modules. U-Boot board features generally use `bool`, string, and numeric options and are linked into the U-Boot image; do not apply Linux's `=m` module model to U-Boot. The projects share Kconfig's core language and configuration flow, but their symbols, defconfigs, generated files, and build targets remain independent.

`choice` expresses mutually exclusive options, such as selecting one implementation or default source. `default` is used when the user has not overridden a value; it is not a force-enable directive. `def_bool` and `def_tristate` combine a type with a default expression.

## 3. `depends on`: visibility and value limits

Menu structure and dependencies jointly constrain a symbol. Dependencies from parent menus propagate to their children; if a `depends on` condition is false, an option may disappear from `menuconfig`, and a previously saved value can be recalculated to a permitted value. Kconfig uses three-valued logic, and multiple dependencies generally behave like logical AND.

In Rockchip Linux 6.1, `sound/soc/rockchip/Kconfig` makes the I2S/TDM driver depend on Rockchip ASoC support and the clock framework, in this form:

```Kconfig
config SND_SOC_ROCKCHIP_I2S_TDM
	tristate "Rockchip I2S/TDM Device Driver"
	depends on HAVE_CLK && SND_SOC_ROCKCHIP
```

If the option is missing from the menu, first inspect parent options such as `SND_SOC`, `SND_SOC_ROCKCHIP`, `HAVE_CLK`, and the actual Kconfig definition in the checked-out tree. Do not start by forcing `CONFIG_SND_SOC_ROCKCHIP_I2S_TDM=y` into `.config`: the next configuration run can clear or rewrite a value whose dependencies are unmet.

`depends on` also limits the maximum value. If a dependency is `m`, a dependent tristate cannot be `y`. A greyed-out item and a symbol that is entirely absent are different cases; pressing `/` in `menuconfig` usually shows the definition location and dependency chain.

## 4. `select` and `imply`: use reverse dependencies carefully

`select FOO` raises the minimum value of `FOO` from the user's option, but does not fully check `FOO`'s own dependencies. This can create a combination that cannot build safely. Kernel Kconfig guidance therefore recommends using `select` carefully, generally for hidden helper symbols without additional dependencies.

`imply FOO` is a weaker recommendation: it tends to enable `FOO`, but a user or direct dependency can still turn it off. A visible hardware driver should normally express its prerequisites with `depends on`, rather than `select` another driver with complex dependencies.

```Kconfig
config DRIVER_A
	tristate "Driver A"
	depends on I2C

config DRIVER_A_HELPER
	bool
	select GENERIC_HELPER
```

Here the visible driver declares its bus requirement; `select` is reserved for a hidden helper without complex prerequisites. Do not copy this pattern blindly: inspect the selected symbol's definition and constraints first.

## 5. `.config`, defconfig, and generated files

- **`defconfig`**: a product or board starting configuration, usually a compact set of differences from defaults for easier review and maintenance. It is not necessarily the complete final `.config`.
- **`.config`**: the resolved configuration for the current source tree, architecture, and dependencies. After switching branches or Kconfig definitions, an old config may gain new options, retain removed ones, or resolve to different defaults.
- **Generated configuration files**: Kconfig/Kbuild converts options into Make-readable files such as `auto.conf` and headers for C code. These are normally regenerated by the build system; they should not be the sole product configuration source.

U-Boot also has a compatibility layer for its older configuration system: Kconfig generates configuration files, while the build can still produce `include/config.h`, `include/autoconf.mk`, and SPL/TPL compatibility files; some legacy macros remain in `include/configs/<board>.h`. Define new configuration options in Kconfig rather than assuming U-Boot and Linux have identical generated-file layouts.

Common kernel commands:

```bash
# Rockchip Linux 6.1; this seed still needs the actual board configuration
make ARCH=arm64 rockchip_linux_defconfig
make ARCH=arm64 menuconfig
make ARCH=arm64 olddefconfig
make ARCH=arm64 savedefconfig
```

U-Boot uses a target board defconfig. This Rockchip U-Boot branch includes `rk3588_defconfig`:

```bash
make rk3588_defconfig
make menuconfig
make olddefconfig
make savedefconfig
```

Do not treat `make defconfig` as a universal board configuration: in U-Boot this shortcut is generally for sandbox. For RK3588, use the target board/BSP defconfig. After saving a compact configuration, review the defconfig diff and regenerate `.config` in a clean output directory to confirm that the required settings are retained.

## 6. From `CONFIG_*` to an object file

Kconfig affects output only when a makefile or C source consumes the symbol. For example, Kbuild often uses:

```make
obj-$(CONFIG_SND_SOC_ROCKCHIP_I2S_TDM) += rockchip_i2s_tdm.o
```

For `CONFIG_...=y`, the object joins the built-in target; for `m`, it is built as a module; for `n`, it is omitted. C source can also use `#if IS_ENABLED(CONFIG_FOO)` around optional code. If a menu says enabled but an object is missing, trace three things: the final `.config` value, the Makefile's `obj-*` condition, and whether the build log visits that directory. Also verify the output directory and source tree; it is easy to inspect configuration A while compiling configuration B.

## 7. RK3588 example: Kconfig and device tree do different jobs

Rockchip U-Boot's `configs/rk3588_defconfig` enables SoC-related settings such as `CONFIG_ARCH_ROCKCHIP=y` and `CONFIG_ROCKCHIP_RK3588=y`. Linux has its own Kconfig symbols, including `CONFIG_ARCH_ROCKCHIP` and driver options such as `CONFIG_SND_SOC_ROCKCHIP_I2S_TDM`. The same `CONFIG_` prefix appears in both projects, but the symbols belong to separate source trees and separate build outputs.

For I2S/TDM, Kconfig makes the driver eligible for compilation. The RK3588/board device tree's `compatible`, `status`, pinctrl, clocks, DMA, and sound-card links describe runtime device instances and connections. A driver compiled into the kernel will not probe if the DTS node is disabled; a DTS node marked `okay` cannot work if the driver was not built. Check `.config`, the actual DTB, driver-binding logs, and the board schematic together.

```text
Kconfig allows the driver to be built
       + target .config selects it as y/m
       + DTS describes a compatible, enabled device
       + board clocks/power/pinctrl/wiring are correct
       ↓
probe can succeed and the device can operate
```

## 8. Preserving kernel configuration in Buildroot and Yocto

Buildroot provides `make linux-menuconfig` to edit kernel settings and `make linux-update-defconfig` to save them. Save into a version-controlled board configuration rather than keeping only the full `.config` from one build directory.

Yocto's kernel recipe assembles the final `.config` from a `defconfig` or configuration fragments. In the correct build environment, run `menuconfig` for the selected kernel provider, capture only intended changes with `diffconfig`/configuration fragments, and store those fragments in a product layer. Do not maintain hand edits to `tmp/work/.../.config`; BitBake configuration tasks can regenerate it. After changing a kernel branch or commit, verify that every fragment still applies and that the symbols still exist.

The companion build articles show the Rockchip kernel default-branch setup: [Buildroot + RK3588](/posts/en/buildroot-from-zero/) · [Yocto + RK3588](/posts/en/yocto-from-zero/).

## 9. Symptoms and a practical debug order

| Symptom | Check first | Next step |
| --- | --- | --- |
| Symbol not found in the menu | Spelling, source branch, parent menus, and dependencies | Search with `/`; read the definition and full dependency chain |
| `.config` changes the option back to `n` | `depends on`, architecture selection, Kconfig changes | Run `olddefconfig`, diff before/after, and find the first unmet dependency |
| `select` causes missing symbols or type problems | The selected symbol's own dependencies, prompt, and tristate value | Fix the dependency model instead of forcing an incompatible combination |
| Option is `y` but object was not built | `.config` used by this build, Makefile condition, and directory traversal | Inspect `V=1` output and `obj-y` / `obj-m` conditions |
| Driver compiles but device does not probe | Whether the loaded DTB matches, compatible/status, and resources | Check booted DTB, pinctrl/clocks/reset, and probe logs |
| Saved config disappears in Yocto/Buildroot | Whether it was saved in a versioned layer/defconfig | Regenerate from the official build system and inspect the final config |

## Source and documentation references

- [Rockchip Linux kernel default repository and `develop-6.1` branch](https://github.com/rockchip-linux/kernel/tree/develop-6.1) · [Kconfig language guide in the same source snapshot](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/Documentation/kbuild/kconfig-language.rst)
- [Rockchip kernel `sound/soc/rockchip/Kconfig`](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/sound/soc/rockchip/Kconfig) · [RK3588 kernel defconfig](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/arch/arm64/configs/rockchip_linux_defconfig)
- [Official U-Boot Kconfig documentation](https://docs.u-boot.org/en/latest/develop/kconfig.html) · [Rockchip U-Boot `next-dev`](https://github.com/rockchip-linux/u-boot/tree/next-dev) · [`rk3588_defconfig`](https://github.com/rockchip-linux/u-boot/blob/1c535d65b8509f388d09e49fb6961f49fda35a1d/configs/rk3588_defconfig)
- [Buildroot manual: kernel configuration](https://buildroot.org/downloads/manual/manual.html) · [Yocto 6.0.2 Kernel Development Manual](https://docs.yoctoproject.org/6.0.2/kernel-dev/common.html) · [Yocto Git source revision variables](https://docs.yoctoproject.org/6.0.2/ref-manual/variables.html#term-SRCREV)

Related reading: [Buildroot from scratch](/posts/en/buildroot-from-zero/) · [Yocto from scratch](/posts/en/yocto-from-zero/) · [RK3588 hardware and driver knowledge base](/knowledge-base/en/).
