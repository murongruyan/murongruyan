# ColorOS 温控解除与墓碑增强模块 (Thermal Killer & Tombstone)

## 简介 / Introduction
这是一个专为 ColorOS 设计的 Magisk 模块，旨在通过底层 Hook 技术彻底解除系统温控限制，并开启完整的墓碑机制以优化功耗。

与传统的简单的“删除温控文件”不同，本模块采用了更高级的 **动态注入 (LD_PRELOAD)** 技术，能够欺骗系统温控服务，使其误以为设备始终处于低温状态，从而彻底解决游戏锁帧、降亮度等问题。

## 核心功能 / Features

### 1. 智能温控欺骗 (Smart Thermal Spoofing)
*   **原理**: 使用 `LD_PRELOAD` 技术将 `libthermal_hook.so` 注入到系统核心温控服务 `horae` 进程中。
*   **读取劫持 (Read Hook)**: 劫持 `read` 和 `pread` 系统调用。当 `horae` 读取传感器温度文件（如 `/sys/class/thermal/thermal_zone*/temp`）时，Hook 库会拦截请求并返回伪造的低温数值（默认 36℃）。
    *   *效果*: 无论手机真实温度多高，系统都认为只有 36℃，因此不会触发任何降频、锁帧或温控策略。
*   **写入拦截 (Write Hook)**: 劫持 `write` 系统调用。拦截 `horae` 对系统温控节点的写入操作，防止其修改 CPU/GPU 频率或调度策略。

### 2. 墓碑机制增强 (Tombstone Enabler)
*   解锁 ColorOS 底层的深度休眠（墓碑）功能。
*   允许后台应用进入“真·暂停”状态，大幅减少后台 CPU 占用，提升待机续航。

### 3. 稳定守护 (Daemon Monitor)
*   内置 `thermal_monitor` C 语言编写的守护进程。
*   实时监控 `horae` 进程状态，一旦发现 Hook 失效或进程重启，立即重新注入，确保温控失效永不掉线。

## 目录结构 / Structure
*   `hook_write_v2.c`: 核心 Hook 库源码，实现 `read`/`write`/`open` 的劫持逻辑。
*   `thermal_monitor_v2.c`: 守护进程源码，负责通过 `inotify` 监控文件和进程状态。
*   `compile_final.bat`: Windows 平台下的一键编译脚本（需 NDK）。
*   `module-common/`: 两个模块共用的安装脚本、启动脚本、动态温控脚本、`META-INF` 和 `bin/` 二进制资源。
*   `ColorOS淦残温控并仅挂载freezerV2(frozen)/`: freezerV2 变体，仅保留 `module.prop`。
*   `ColorOS移除温控并开启ColorOS墓碑完全体/`: 墓碑完全体变体，仅保留 `module.prop` 和 `data/` 差异文件。
*   `.github/workflows/build-modules.yml`: GitHub Actions 工作流，按“公共层 + 变体层”自动打包并发版。

## 编译说明 / Build
本项目依赖 Android NDK 进行编译。

1.  确保电脑已安装 Android NDK，建议优先使用 `NDK 30.0.14904198` 或兼容的 `r30` 系版本。
2.  优先通过环境变量 `ANDROID_NDK_ROOT` 或 `NDK_ROOT` 指向你的本地 NDK；如果未设置，`compile_final.bat` 会继续尝试本机常见的 `r30-beta1 / r30` 路径，最后才回退旧路径。
3.  双击运行 `compile_final.bat`。
4.  编译成功后，会生成 `libthermal_hook.so` 和 `thermal_monitor` 两个文件。
5.  本地打包时，将这两个文件放入 `module-common/bin/` 中。
6.  GitHub Actions 发版时会在 Ubuntu Runner 上使用 `NDK 30.0.14904198` 自动重新编译这两个二进制，再组装成最终模块包。

## 免责声明 / Disclaimer
*   本模块通过修改系统底层行为实现功能，属于高风险操作。
*   解除温控会导致设备温度升高，长期高温运行可能会加速硬件老化或导致电池鼓包。
*   作者不对因使用本模块导致的任何手机损坏、数据丢失或硬件故障负责。
*   请确保你了解自己在做什么，并自行承担风险。

## 协议 / License
GNU General Public License v3.0
