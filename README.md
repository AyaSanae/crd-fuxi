# crDroid 16 · Xiaomi 13 (fuxi)

非官方 crDroid 16（Android 16 / LineageOS 23.2）编译备忘。脚本只负责整理清单和覆盖层，**不要在 Windows 上拉 AOSP**。真源码在 Linux，当前 AutoDL 路径是 `/root/autodl-tmp/crd`。

---

## 整条流程（先看这个）

两套走法：日常用脚本；脚本不好使或你想自己控 `breakfast` 就走手动。两条路读的是同一棵源码树。

```text
Windows 本目录（脚本 / overlay / build.conf）
        │  上传到 Linux，不要在 Windows 上 repo sync
        ▼
① 去 CRLF → ② 装依赖（一次）→ ③ sync 拉源码
        ▼
④ 改源码树里的 build.conf（用户名 / LTO / -j）
        ▼
⑤ A  ./build-fuxi.sh          ← 推荐
   B  手动 source + breakfast + mka
        ▼
out/target/product/fuxi/*.zip
```

### 第一次（空机器）

在 Linux 上，假设脚本放在 `~/tmp-scripts`，源码要落到 `/root/autodl-tmp/crd`：

```bash
cd ~/tmp-scripts
sed -i 's/\r$//' *.sh
chmod +x sync-crdroid-fuxi.sh build-fuxi.sh

# 代理：GitHub / crDroid / LOS / TheMuppets 走这个；AOSP 走清华，不占代理
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890

# ① 只装依赖，不拉代码
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh --install-deps --skip-sync

# ② 改旁边的 build.conf（编译人、KERNEL_LTO、MAKE_JOBS…）再拉
#    或把参数写在命令行，见下面「脚本怎么用」
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh

# ③ 进源码树编译（脚本会把自己拷进树里）
cd /root/autodl-tmp/crd
./build-fuxi.sh
```

第一次 sync 很久，中断后用同一条 `SRC_DIR=... ./sync-crdroid-fuxi.sh` 或 `--sync-only` 续传。

### 源码已经在、接着编

```bash
# 若刚从 Windows 又传了一份新脚本 / overlay：
cd ~/tmp-scripts
sed -i 's/\r$//' *.sh
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh --skip-sync
# 刷新 overlay、vendor/extra、build-fuxi.sh；不覆盖已有 build.conf，只补新键

cd /root/autodl-tmp/crd
# 按需改 build.conf
./build-fuxi.sh
```

不用清整个 `out`。只改了 `KERNEL_LTO` 时，`build-fuxi.sh` 会自己清 `KERNEL_OBJ`。

### 编挂了再续

```bash
cd /root/autodl-tmp/crd
./build-fuxi.sh
# 或手动（同一 shell 里已经 source 过就不用再 breakfast）：
mka bacon -j4
```

---

## 脚本怎么用

### `build.conf` —— 所有可调项的默认来源

放在脚本旁边。`sync` 第一次会拷进源码树 `SRC_DIR/build.conf`。之后以**源码树那份**为准，sync 不会覆盖，只补缺失键。

`./build-fuxi.sh` 会读它。直接 `brunch` / 裸 `breakfast` **不读**，必须自己 `source vendor/extra/env.sh` 或导出同样的变量。

| 键 | 默认 | 作用 |
| --- | --- | --- |
| `BUILD_USERNAME` | `crdroid` | `ro.build.user`，不跟当前 Linux 用户 |
| `BUILD_HOSTNAME` | `fuxi` | `ro.build.host`，不跟 hostname |
| `CRDROID_MAINTAINER` | 同 username | 设置里的维护者 |
| `KERNEL_LTO` | `thin` | `none` / `thin` / `full` / 空=设备树默认 |
| `SYNC_JOBS` | `4` | `repo sync -j`，清华太高会 503 |
| `MAKE_JOBS` | `4` | `mka -j`，容器里别上 8 |
| `USE_CCACHE` | `1` | `0` 关闭 |
| `CCACHE_SIZE` | `20G` | 上限 |
| `CCACHE_DIR` | 空 | 空则 `/root/autodl-tmp/.ccache` 或 `~/.cache/ccache` |
| `AOSP_MIRROR` | 清华 | 空=走 googlesource（会吃代理） |
| `HTTP_PROXY` / `HTTPS_PROXY` | 空 | 空=用当前环境的 `http_proxy` |

命令行参数会盖过 conf。

### `sync-crdroid-fuxi.sh` —— 拉代码 + 铺 overlay

**只在 Linux 跑。** 负责：`repo init` crDroid、写 `.repo/local_manifests/fuxi.xml`、`repo sync`、拷 MiuiCamera overlay、写 `vendor/extra`（身份 / LTO / env.sh）、拷 `build-fuxi.sh`。

```bash
# 通用形式
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh [选项…]
```

`SRC_DIR` 也可用 `--src`。不写则默认 `~/android/crdroid`。

| 选项 | 干什么 |
| --- | --- |
| （无参数） | init（若还没有）+ 写 manifest + sync + 装 overlay/身份 |
| `--install-deps` | `apt` 装编译依赖和 ccache（要 sudo） |
| `--skip-sync` | 写 manifest / 装 overlay / 写 extra，**不** `repo sync`。源码已在、只更新脚本时用 |
| `--sync-only` | 已 init 过，只更新 manifest 再 sync |
| `--manifest-only` | 只写 `fuxi.xml`，不 init、不 sync |
| `--branch 16.0\|15.0` | crDroid 分支。16.0↔LOS 23.2，15.0↔22.2 |
| `--jobs N` | sync 并发，默认 4 |
| `--aosp-mirror URL` | 改 AOSP 镜像 |
| `--no-tuna` | AOSP 不走清华，改走代理直连 googlesource |
| `--proxy URL` | 同时设 `http_proxy`/`https_proxy`（非 AOSP） |
| `--vendor themuppets\|extract` | 默认 themuppets 才能直接编；extract 要自己抽 blob |
| `--miuicamera` / `--no-miuicamera` | 默认开 overlay；关了就不拷 |
| `--hyperos-zip FILE` | sync 完从 HyperOS 官方包抽 MiuiCamera APK/JNI |
| `--build-user` `--build-host` `--maintainer` | 盖过 conf 里的显示名 |
| `--kernel-lto none\|thin\|full` | 盖过 conf，写入 `BoardConfigExtra.mk` |
| `--make-jobs N` | 只记到环境/提示，真正编译看 `build-fuxi.sh` 读的 conf |
| `-h` | 帮助 |

常用组合：

```bash
# 只装依赖
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh --install-deps --skip-sync

# 正常拉（AOSP 清华 + 其余走已 export 的代理）
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh

# 命令行指定代理和身份
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh \
  --proxy http://127.0.0.1:7890 \
  --build-user AyaSanae --build-host fuxi --maintainer Aya \
  --kernel-lto thin

# 源码有了，只把新 overlay / 新 build-fuxi.sh 铺进去
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh --skip-sync

# 抽 Leica
SRC_DIR=/root/autodl-tmp/crd ./sync-crdroid-fuxi.sh --sync-only \
  --hyperos-zip /path/to/fuxi-hyperos.zip
```

sync 结束时源码树里会有：

- `.repo/local_manifests/fuxi.xml`
- `device/xiaomi/miuicamera-fuxi/`（overlay 副本）
- `vendor/extra/product.mk` `BoardConfigExtra.mk` `build_info.mk` `env.sh`
- `build-fuxi.sh`、`build.conf`（后者仅当树里还没有）

### `build-fuxi.sh` —— 一键开编

可以放在脚本目录，用 `SRC_DIR=... ./build-fuxi.sh`；sync 之后也在源码树根目录，进树直接跑。

```bash
cd /root/autodl-tmp/crd
./build-fuxi.sh              # userdebug
./build-fuxi.sh user         # 正式包
./build-fuxi.sh userdebug    # 显式写变体
```

脚本在树外时：

```bash
SRC_DIR=/root/autodl-tmp/crd ./build-fuxi.sh
```

它按顺序做：

1. 读 `SRC_DIR/build.conf`（没有再读脚本旁边那份）
2. `export BUILD_USERNAME` `BUILD_HOSTNAME` `KBUILD_BUILD_*`
3. 按 `KERNEL_LTO` 写 `vendor/extra/BoardConfigExtra.mk`；和上次不同就删 `KERNEL_OBJ`
4. `USE_CCACHE=1` `CCACHE_EXEC` `CCACHE_DIR`，`ccache -M`
5. `source build/envsetup.sh`（**不加** `set -euo`）
6. `breakfast fuxi $VARIANT`
7. `mka bacon -j$MAKE_JOBS`

**不要**给这个脚本或它 source 的环境加 `set -euo pipefail`。

产物：`out/target/product/fuxi/`，刷机包一般是 `crDroidAndroid-*-fuxi-*.zip`。

---

## 手动编译流程

和 `build-fuxi.sh` 做的事相同，只是自己敲。适合：已经 `breakfast` 过、只想续 `mka`；或要改 lunch 变体、先 `mka bootimage` 之类。

**前提：** 已经 `sync` 过，`vendor/extra/env.sh` 存在。新开的 SSH 窗口环境是空的，必须重来一遍 1–4。

在**同一条 shell**里，不要 `set -e` / `set -u` / `set -o pipefail`：

```bash
cd /root/autodl-tmp/crd

# 1) 身份 + ccache（不 source 这个，关于手机会变成 root@容器名，ccache 也不走）
source vendor/extra/env.sh

# 若 env.sh 是旧的、没有 ccache，补这三行（目录要和查统计时一致）
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR=/root/autodl-tmp/.ccache
mkdir -p "$CCACHE_DIR"
ccache -M 20G
ccache -o compression=true

# 2) 内核 LTO：改 build.conf 不够，手动编要自己保证 mk 里有
#    脚本编会自动写；手动可以看一眼
grep KERNEL_LTO vendor/extra/BoardConfigExtra.mk
# 没有或要改：
#   echo 'KERNEL_LTO := thin' >> vendor/extra/BoardConfigExtra.mk
# 从 full/none 换成 thin 必须清内核中间文件，否则仍按旧配置链：
#   rm -rf out/target/product/fuxi/obj/KERNEL_OBJ

# 3) Android 编译环境。这一步会定义 breakfast / mka / lunch
source build/envsetup.sh

# 4) 选设备和变体。只需每个新 shell 做一次
breakfast fuxi userdebug
# 等价：lunch lineage_fuxi-bp2a-userdebug
# user 包：breakfast fuxi user

# nsjail / sched_setaffinity 警告可忽略

# 5) 开编。bacon = 整包。-j 跟机器内存/cgroup 走，AutoDL 用 4
mka bacon -j4

# 只编内核 / 只编 boot：
# mka bootimage -j4
```

中途挂了、环境还在：

```bash
# 不要再 source 一遍也可以
mka bacon -j4
```

窗口断了、重新 SSH：从 `source vendor/extra/env.sh` 重新走 1–5。`out/` 留着就是增量。

查 ccache 必须带同一个目录：

```bash
echo "$USE_CCACHE $CCACHE_EXEC $CCACHE_DIR"
CCACHE_DIR=/root/autodl-tmp/.ccache ccache -s
```

手动编时若跳过 `env.sh` / 那三个 export，`ccache -s` 就会一直是 `0.0 / 30G`。

`brunch fuxi` = `breakfast` + `mka bacon`，但**不会**读 `build.conf`，也**不会**写 LTO、开 ccache。要 `brunch` 也得先 `source vendor/extra/env.sh`。

---

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

依赖含 `ccache`、`repo`、`git-lfs`。怎么装、怎么拉、怎么编见上文「整条流程」和「脚本怎么用」。

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

## 不要做的事

- 不要把 fuxi-dev 的 22.2 common/vendor 和 LOS 23.2 设备树拼在一起
- 不要为了 MiuiCamera 去拉 Xiaomi Framework
- 不要在 `build-fuxi.sh` / 手动 `source envsetup` 时开 `set -euo`
- 不要把 `action cancelled when ninja exited` 当 AIDL 源码 bug
- 不要用 `neverallow` 去给 App 开 QCOM DSP 节点
- 不要用 `free -h` 判断 AutoDL 容器内存够不够
