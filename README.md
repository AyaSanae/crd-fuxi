# crDroid 16 · Xiaomi 13 (fuxi)

非官方 crDroid 16（Android 16 / LineageOS 23.2）编译备忘。脚本只负责整理清单和覆盖层，**不要在 Windows 上拉 AOSP**。真源码在 Linux，当前 AutoDL 路径是 `/root/autodl-tmp/crd`。

## 目录里有什么

| 文件 | 作用 |
| --- | --- |
| `build.conf` | 编译人、内核 LTO、ccache、并行、镜像/代理 |
| `sync-crdroid-fuxi.sh` | `repo init/sync` + 装 overlay / vendor/extra |
| `build-fuxi.sh` | 读 conf，写 LTO，开 ccache，`breakfast` + `mka bacon` |
| `local_manifests/fuxi.xml` | 给人手放 `.repo/local_manifests/` 的模板 |
| `overlays/miuicamera-fuxi/` | MiuiCamera 设备侧（不拉小米框架） |
| `README.md` | 本文 |

## 能编的栈（不要混 fuxi-dev）

fuxi-dev 基本停在 lineage-22.2 staging，和 crDroid 16 混会编不过。用：

| 仓库 | 落盘 |
| --- | --- |
| LineageOS `android_device_xiaomi_fuxi` | `device/xiaomi/fuxi` |
| LineageOS `android_device_xiaomi_sm8550-common` | `device/xiaomi/sm8550-common` |
| LineageOS `android_kernel_xiaomi_sm8550` | `kernel/xiaomi/sm8550` |
| LineageOS `android_kernel_xiaomi_sm8550-modules` | `kernel/xiaomi/sm8550-modules` |
| LineageOS `android_kernel_xiaomi_sm8550-devicetrees` | `kernel/xiaomi/sm8550-devicetrees` |
| LineageOS `android_hardware_xiaomi` | `hardware/xiaomi` |
| TheMuppets `proprietary_vendor_xiaomi_fuxi` | `vendor/xiaomi/fuxi` |
| TheMuppets `proprietary_vendor_xiaomi_sm8550-common` | `vendor/xiaomi/sm8550-common` |

分支：`crDroid 16.0` ↔ `lineage-23.2`。15.0 才用 `lineage-22.2`。

`vendor/extra/{product.mk,BoardConfigExtra.mk}` 会被 Lineage/crDroid 自动 include，用来挂 MiuiCamera、编译身份、`KERNEL_LTO`，`repo sync` 冲不掉。

## 环境

Ubuntu/Debian。磁盘建议 ≥ 400GB。内存看 **cgroup 限额**，不是 `free -h` 的宿主机容量。AutoDL 出现过宿主机 251Gi 可用、Swap 0，内核 LTO 仍被 137 杀掉。

```bash
# 上传脚本后先去 CRLF，否则报 /usr/bin/env: ‘bash\r’
sed -i 's/\r$//' *.sh

chmod +x sync-crdroid-fuxi.sh build-fuxi.sh
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh --install-deps --skip-sync
```

依赖含 `ccache`、`repo`、`git-lfs`。ccache 预算默认 20G（可在 `build.conf` 改）。

## `build.conf`

改完用 `./build-fuxi.sh`。直接 `brunch` 不读这份文件。

```bash
# 关于手机，不跟编译机 hostname
BUILD_USERNAME=crdroid
BUILD_HOSTNAME=fuxi
CRDROID_MAINTAINER=crdroid

# 内核 LTO: none | thin | full | 留空=设备树默认
# full 在 AutoDL 上 ld.lld vmlinux.o 容易 Error 137
KERNEL_LTO=thin

SYNC_JOBS=4          # 清华 AOSP 太高会 503
MAKE_JOBS=4          # 容器里 -j8 容易把 ninja 整进程掐死

USE_CCACHE=1
CCACHE_SIZE=20G
CCACHE_DIR=          # 空= /root/autodl-tmp/.ccache 或 ~/.cache/ccache

AOSP_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/git/AOSP
HTTP_PROXY=          # 非 AOSP 走这个；空则用环境变量
HTTPS_PROXY=
```

改 `KERNEL_LTO` 后再跑 `build-fuxi.sh`，脚本会重写 `vendor/extra/BoardConfigExtra.mk` 并清 `out/target/product/fuxi/obj/KERNEL_OBJ`。

源码树里若已有旧 `build.conf`，`sync` **不会覆盖**，只补缺失键。

## 拉源码

```bash
# AOSP 走清华（进 no_proxy）；GitHub / crDroid / LOS / TheMuppets 走代理
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890

SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh
# 已 init 过只更新:
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh --sync-only
```

清华并发默认 `-j4`。中断后同一条命令可续传。

## 编译

```bash
cd /root/autodl-tmp/crd
./build-fuxi.sh                 # 默认 userdebug
# ./build-fuxi.sh user
```

脚本会：读 conf → 写 `KERNEL_LTO` → `USE_CCACHE=1` + `CCACHE_EXEC` + `CCACHE_DIR` → `source envsetup` → `breakfast fuxi` → `mka bacon -j$MAKE_JOBS`。

**不要**给 `build-fuxi.sh` 加 `set -euo pipefail`。`envsetup.sh` 里有未绑定变量和返回 1 的探测，`set -u` 报 `TOP: unbound variable`，`set -e` 会在 lunch 后静默退出。

手动编必须先带环境：

```bash
source vendor/extra/env.sh
source build/envsetup.sh
breakfast fuxi userdebug
mka bacon -j4
```

产物：`out/target/product/fuxi/`。

`breakfast` 里 nsjail / `sched_setaffinity` 在 AutoDL 上常见，可忽略。

## MiuiCamera

不依赖 Xiaomi Framework / `miui.jar`。做法是本地 overlay + 从 **fuxi 的 HyperOS 官方包**抽 APK/JNI。

没抽之前 `inherit-product-if-exists`，ROM 仍用 Aperture，能编过。抽完再编一次才会盖掉 Aperture。

```bash
./sync-crdroid-fuxi.sh --sync-only --hyperos-zip /path/to/fuxi-hyperos.zip
# 或
cd /root/autodl-tmp/crd/device/xiaomi/miuicamera-fuxi
./extract-files.py /path/to/fuxi-hyperos.zip
```

overlay 里已经去掉会炸编译的 sepolicy：

- `vendor_panel_info_prop`：LOS 没有这个 type
- `vendor_qdsp_device` / `vendor_xdsp_device`：QCOM sm8550 `neverallow`，App 不能直接写 DSP
- notch 用 `ro.miui.notch=1`

后面若再报 `unknown type` 或 `neverallow ... from device/xiaomi/miuicamera-fuxi/sepolicy/...`，删对应那一行即可。

## 已经踩过的坑

### 1. ` /usr/bin/env: ‘bash\r’`

Windows CRLF。`sed -i 's/\r$//' *.sh`。sync/build 脚本拷进源码树时会再去一次 `\r`。

### 2. `TOP: unbound variable` / lunch 后没下文

对 `envsetup.sh` 开了 `set -u` / `set -e`。用现在的 `build-fuxi.sh`，或手动 `source` 时不要 `set -euo`。自己用 python 插 `set +u` 再 `set -u` 也不行。

### 3. 内核 `vmlinux.o` Killed / Error 137

Clang LTO 链 `vmlinux` 被 SIGKILL。多半是 **cgroup 内存**，不是 `free -h` 看起来很大。

```bash
# build.conf
KERNEL_LTO=thin    # 还 137 就改 none
MAKE_JOBS=4
```

改 LTO 必须清 `KERNEL_OBJ`（`build-fuxi.sh` 会做）。

```bash
dmesg -T | tail -50
cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.current
```

### 4. `ccache -s` 一直 `0.0 / 30.0`

只 `ccache -M` 没用。AOSP 不自带 ccache，必须：

```text
USE_CCACHE=1
CCACHE_EXEC=/usr/bin/ccache
CCACHE_DIR=固定目录
```

手动 `breakfast` 没导这些变量，缓存就是空的。查统计要带同一个目录：

```bash
CCACHE_DIR=/root/autodl-tmp/.ccache ccache -s
```

新版默认目录可能是 `~/.cache/ccache`，和你设上限的不是同一处。编到 8% 时主要是 Java / sepolicy / 内核 LTO，本来也几乎不进 ccache。

### 5. `error: action cancelled when ninja exited`

**不是** AIDL / dex2oat 源码错。ninja 整进程没了（OOM、盘满、SSH 断、被杀），正在跑的任务陪葬。真失败会有 `aidl` 报错或 `Dex2oat failed to compile a boot image`。

```bash
dmesg -T | tail -50
df -h /root/autodl-tmp /root
```

降 `MAKE_JOBS`，不要清整个 `out`，接着 `mka bacon -j4`。

### 6. sepolicy：`unknown type vendor_panel_info_prop`

`checkpolicy` 失败，拦编译。LOS 没有这个 type。overlay 已删。功能上只是读屏参；notch 已用 `ro.miui.notch` 兜。

### 7. sepolicy：`neverallow` × `vendor_qdsp_device` / `vendor_xdsp_device`

`secilc` 失败。QCOM sm8550 禁止 `platform_app` 写 DSP 设备。DSP 应走 camera HAL。overlay 已删那两行。Settings 的 `Missing class AppFunctionContext` 只是 R8 警告，可忽略。

### 8. 清华 AOSP 503

`SYNC_JOBS=4`，不要按 `nproc` 拉 AOSP。

## 下次在 AutoDL 上续编

把本目录（至少 `build.conf`、两个 `.sh`、`overlays/`）上传到机器后：

```bash
sed -i 's/\r$//' *.sh
export http_proxy=... https_proxy=...     # 若还要 sync
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh --skip-sync
# 会刷新 overlay / vendor/extra / build-fuxi.sh，不覆盖已有 build.conf，只补新键

cd /root/autodl-tmp/crd
# 按需改 build.conf 里的 KERNEL_LTO / MAKE_JOBS / 用户名
./build-fuxi.sh
```

## 不要做的事

- 不要把 fuxi-dev 的 22.2 common/vendor 和 LOS 23.2 设备树拼在一起
- 不要为了 MiuiCamera 去拉 Xiaomi Framework
- 不要在 `build-fuxi.sh` / 手动 `source envsetup` 时开 `set -euo`
- 不要把 `action cancelled when ninja exited` 当 AIDL 源码 bug
- 不要用 `neverallow` 去给 App 开 QCOM DSP 节点
- 不要用 `free -h` 判断 AutoDL 容器内存够不够
