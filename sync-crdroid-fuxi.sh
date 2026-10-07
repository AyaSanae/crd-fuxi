#!/usr/bin/env bash
# =============================================================================
#  Xiaomi 13 (fuxi) — crDroid 源码拉取脚本
#  在 Linux 编译机上执行。不要在 Windows 上跑。
#
#  拉完后:
#    ./build-fuxi.sh
#  不要对 build-fuxi.sh 加 set -euo，envsetup.sh 不兼容。
#
#  用法:
#    chmod +x sync-crdroid-fuxi.sh
#    ./sync-crdroid-fuxi.sh                  # 默认 crDroid 16.0 + LOS 23.2
#    ./sync-crdroid-fuxi.sh --branch 15.0    # crDroid 15.0 + LOS 22.2
#    ./sync-crdroid-fuxi.sh --manifest-only  # 只写 local_manifest，不 sync
#    ./sync-crdroid-fuxi.sh --install-deps   # 顺带装 Ubuntu 编译依赖
#    SRC_DIR=/data/crdroid ./sync-crdroid-fuxi.sh
# =============================================================================

set -euo pipefail

# ---------- 可改配置 ----------
SRC_DIR="${SRC_DIR:-${HOME}/android/crdroid}"
CRDROID_BRANCH="${CRDROID_BRANCH:-16.0}"
JOBS="${JOBS:-}"
DEVICE="fuxi"

# vendor 来源: themuppets (推荐，拉完就能编) | extract (只拉设备树，blobs 自己从真机/zip 抽)
VENDOR_SOURCE="${VENDOR_SOURCE:-themuppets}"

# 默认集成 MiuiCamera 设备侧（不拉 Xiaomi Framework）。
# APK/JNI 要从 HyperOS zip 抽，没抽之前 inherit-if-exists，ROM 仍用 Aperture，能编过。
INCLUDE_MIUICAMERA="${INCLUDE_MIUICAMERA:-1}"
HYPEROS_ZIP="${HYPEROS_ZIP:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="${SCRIPT_DIR}/overlays/miuicamera-fuxi"

# 关于手机显示的编译人 / 机器名。默认读旁边的 build.conf，不跟本机 hostname。
if [[ -f "${SCRIPT_DIR}/build.conf" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/build.conf"
fi
BUILD_USERNAME="${BUILD_USERNAME:-crdroid}"
BUILD_HOSTNAME="${BUILD_HOSTNAME:-fuxi}"
CRDROID_MAINTAINER="${CRDROID_MAINTAINER:-${BUILD_USERNAME}}"
CCACHE_SIZE="${CCACHE_SIZE:-20G}"
USE_CCACHE="${USE_CCACHE:-1}"
MAKE_JOBS="${MAKE_JOBS:-4}"
if [[ -z "${KERNEL_LTO+x}" ]]; then
    KERNEL_LTO=thin
fi
AOSP_MIRROR="${AOSP_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/git/AOSP}"
# 清华 AOSP 并发太高会 503，默认 4；可用 --jobs 改
JOBS="${JOBS:-${SYNC_JOBS:-4}}"

# ---------- 内部状态 ----------
MANIFEST_ONLY=0
SYNC_ONLY=0
INSTALL_DEPS=0
SKIP_SYNC=0

usage() {
    cat <<'EOF'
用法: ./sync-crdroid-fuxi.sh [选项]

  --branch 16.0|15.0   crDroid 分支。16.0=A16/LOS23.2，15.0=A15/LOS22.2
  --src DIR            源码目录，默认 ~/android/crdroid
  --jobs N             repo sync 并发。清华 AOSP 建议 4，默认 4
  --aosp-mirror URL    AOSP 镜像，默认清华
  --no-tuna            AOSP 不走清华，改走代理直连 googlesource
  --proxy URL          同时设置 http_proxy/https_proxy（GitHub 等非 AOSP）
  --vendor themuppets|extract
                       themuppets: 拉 TheMuppets proprietary blobs（默认可直接编）
                       extract:    不拉 vendor，之后用 extract-files.py 自己抽
  --miuicamera         集成 MiuiCamera（默认开，不依赖小米框架）
  --no-miuicamera      不装 MiuiCamera 覆盖层
  --hyperos-zip FILE   从 HyperOS fuxi 官方包抽出 MiuiCamera APK/JNI
  --build-user NAME    关于手机里显示的编译人（ro.build.user）
  --build-host NAME    关于手机里显示的机器名（ro.build.host）
  --maintainer NAME    crDroid 设置里的维护者
  --kernel-lto none|thin|full
                       内核 LTO，默认读 build.conf（thin）
  --make-jobs N        编译并行，写入源码树 build.conf 提示；默认 4
  --manifest-only      只生成 .repo/local_manifests/fuxi.xml
  --sync-only          已 repo init 过，只更新 manifest 再 sync
  --install-deps       Ubuntu/Debian 上安装编译依赖（需要 sudo）
  --skip-sync          写好 manifest / init 后不 sync
  -h, --help           帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch) CRDROID_BRANCH="$2"; shift 2 ;;
        --src) SRC_DIR="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --aosp-mirror) AOSP_MIRROR="$2"; shift 2 ;;
        --no-tuna) AOSP_MIRROR=""; shift ;;
        --proxy) HTTP_PROXY="$2"; HTTPS_PROXY="$2"; shift 2 ;;
        --vendor) VENDOR_SOURCE="$2"; shift 2 ;;
        --miuicamera) INCLUDE_MIUICAMERA=1; shift ;;
        --no-miuicamera) INCLUDE_MIUICAMERA=0; shift ;;
        --hyperos-zip) HYPEROS_ZIP="$2"; INCLUDE_MIUICAMERA=1; shift 2 ;;
        --build-user) BUILD_USERNAME="$2"; shift 2 ;;
        --build-host) BUILD_HOSTNAME="$2"; shift 2 ;;
        --maintainer) CRDROID_MAINTAINER="$2"; shift 2 ;;
        --kernel-lto) KERNEL_LTO="$2"; shift 2 ;;
        --make-jobs) MAKE_JOBS="$2"; shift 2 ;;
        --manifest-only) MANIFEST_ONLY=1; shift ;;
        --sync-only) SYNC_ONLY=1; shift ;;
        --install-deps) INSTALL_DEPS=1; shift ;;
        --skip-sync) SKIP_SYNC=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数: $1"; usage; exit 1 ;;
    esac
done

case "${CRDROID_BRANCH}" in
    16.0)
        LOS_BRANCH="lineage-23.2"
        LUNCH_HINT="brunch fuxi    # 或 lunch lineage_fuxi-bp2a-userdebug && mka bacon"
        ;;
    15.0)
        LOS_BRANCH="lineage-22.2"
        LUNCH_HINT="brunch fuxi"
        ;;
    *)
        echo "不支持的 crDroid 分支: ${CRDROID_BRANCH}（只要 16.0 或 15.0）"
        exit 1
        ;;
esac

case "${VENDOR_SOURCE}" in
    themuppets|extract) ;;
    *) echo "VENDOR_SOURCE 只能是 themuppets 或 extract"; exit 1 ;;
esac

case "${KERNEL_LTO}" in
    none|thin|full|"") ;;
    *) echo "KERNEL_LTO 只能是 none / thin / full / 空"; exit 1 ;;
esac

# ---------- 依赖说明 ----------
# fuxi-dev 我核对过了：能用的树几乎都停在 lineage-22.2，而且是 staging。
# LineageOS 已经有官方 fuxi / sm8550-common / kernel / modules / dt / hardware。
# 你指定的四份 LOS 源 + 官方 common/hardware + TheMuppets vendor，才能 sync 完直接编。
# 混用 fuxi-dev 的 22.2 common/vendor 和 LOS 23.2 设备树会编不过。
#
# 必备仓库与落盘路径:
#   LineageOS/android_device_xiaomi_fuxi                 -> device/xiaomi/fuxi
#   LineageOS/android_device_xiaomi_sm8550-common        -> device/xiaomi/sm8550-common
#   LineageOS/android_kernel_xiaomi_sm8550               -> kernel/xiaomi/sm8550
#   LineageOS/android_kernel_xiaomi_sm8550-modules       -> kernel/xiaomi/sm8550-modules
#   LineageOS/android_kernel_xiaomi_sm8550-devicetrees   -> kernel/xiaomi/sm8550-devicetrees
#   LineageOS/android_hardware_xiaomi                    -> hardware/xiaomi
#   TheMuppets/proprietary_vendor_xiaomi_fuxi            -> vendor/xiaomi/fuxi
#   TheMuppets/proprietary_vendor_xiaomi_sm8550-common   -> vendor/xiaomi/sm8550-common

write_local_manifest() {
    local dest="$1"
    mkdir -p "$(dirname "${dest}")"

    cat > "${dest}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!--
  Xiaomi 13 (fuxi) local manifest
  crDroid ${CRDROID_BRANCH}  <->  ${LOS_BRANCH}
  由 sync-crdroid-fuxi.sh 生成，不要手改后指望脚本下次还保留你的改动。
-->
<manifest>
  <remote name="los"     fetch="https://github.com/LineageOS/" />
  <remote name="muppets" fetch="https://github.com/TheMuppets/" />

  <!-- 设备树：你指定的 LineageOS fuxi DT -->
  <project name="android_device_xiaomi_fuxi" path="device/xiaomi/fuxi"
           remote="los" revision="${LOS_BRANCH}" />

  <!-- fuxi DT 的 lineage.dependencies：必须有 common -->
  <project name="android_device_xiaomi_sm8550-common" path="device/xiaomi/sm8550-common"
           remote="los" revision="${LOS_BRANCH}" />

  <!-- Kernel / modules / dtbo：你指定的三份 LineageOS 源 -->
  <project name="android_kernel_xiaomi_sm8550" path="kernel/xiaomi/sm8550"
           remote="los" revision="${LOS_BRANCH}" />
  <project name="android_kernel_xiaomi_sm8550-modules" path="kernel/xiaomi/sm8550-modules"
           remote="los" revision="${LOS_BRANCH}" />
  <project name="android_kernel_xiaomi_sm8550-devicetrees" path="kernel/xiaomi/sm8550-devicetrees"
           remote="los" revision="${LOS_BRANCH}" />

  <!-- common.mk 依赖 hardware/xiaomi，平台 manifest 里没有 -->
  <project name="android_hardware_xiaomi" path="hardware/xiaomi"
           remote="los" revision="${LOS_BRANCH}" />
EOF

    if [[ "${VENDOR_SOURCE}" == "themuppets" ]]; then
        cat >> "${dest}" <<EOF

  <!-- proprietary blobs：没有这两份编不起来 -->
  <project name="proprietary_vendor_xiaomi_fuxi" path="vendor/xiaomi/fuxi"
           remote="muppets" revision="${LOS_BRANCH}" />
  <project name="proprietary_vendor_xiaomi_sm8550-common" path="vendor/xiaomi/sm8550-common"
           remote="muppets" revision="${LOS_BRANCH}" />
EOF
    fi

    cat >> "${dest}" <<'EOF'
</manifest>
EOF

    echo "已写入 ${dest}"
}

# AOSP -> 清华镜像；GitHub/LOS/crDroid/TheMuppets -> http_proxy/https_proxy
# 清华域名进 no_proxy，避免镜像再绕一层代理。
setup_fetch_network() {
    if [[ -z "${HTTP_PROXY:-}" && -n "${http_proxy:-}" ]]; then
        HTTP_PROXY="${http_proxy}"
    fi
    if [[ -z "${HTTPS_PROXY:-}" && -n "${https_proxy:-}" ]]; then
        HTTPS_PROXY="${https_proxy}"
    fi
    if [[ -z "${HTTPS_PROXY:-}" && -n "${HTTP_PROXY:-}" ]]; then
        HTTPS_PROXY="${HTTP_PROXY}"
    fi
    if [[ -z "${HTTP_PROXY:-}" && -n "${HTTPS_PROXY:-}" ]]; then
        HTTP_PROXY="${HTTPS_PROXY}"
    fi

    if [[ -n "${HTTP_PROXY:-}" ]]; then
        export http_proxy="${HTTP_PROXY}"
        export HTTP_PROXY="${HTTP_PROXY}"
        export https_proxy="${HTTPS_PROXY}"
        export HTTPS_PROXY="${HTTPS_PROXY}"
        echo "非 AOSP 走代理: ${HTTP_PROXY}"
    else
        echo "警告: 未设置 http_proxy/https_proxy。GitHub / crDroid / LineageOS / TheMuppets 会直连。"
    fi

    local nop="localhost,127.0.0.1,mirrors.tuna.tsinghua.edu.cn,.tuna.tsinghua.edu.cn,.tsinghua.edu.cn"
    if [[ -n "${no_proxy:-}" ]]; then
        nop="${no_proxy},${nop}"
    fi
    export no_proxy="${nop}"
    export NO_PROXY="${nop}"

    if [[ -n "${AOSP_MIRROR}" ]]; then
        local dest="${AOSP_MIRROR%/}/"
        git config --global url."${dest}".insteadOf https://android.googlesource.com
        git config --global http.https://mirrors.tuna.tsinghua.edu.cn.proxy ""
        echo "AOSP 走镜像: ${AOSP_MIRROR}  （不走代理）"
    else
        echo "AOSP 不走清华镜像，将随 https_proxy 拉 googlesource"
    fi
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "缺少命令: $1"
        exit 1
    }
}

install_deps_ubuntu() {
    echo "==> 安装 Ubuntu/Debian 编译依赖"
    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        bc bison build-essential ccache curl erofs-utils flex \
        g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick \
        protobuf-compiler python3-protobuf python-is-python3 \
        lib32readline-dev lib32z1-dev libdw-dev libelf-dev libgnutls28-dev \
        lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush \
        rsync schedtool squashfs-tools xsltproc xxd zip zlib1g-dev \
        libncurses-dev libncurses6
    setup_ccache
}

default_ccache_dir() {
    if [[ -n "${CCACHE_DIR:-}" ]]; then
        printf '%s\n' "${CCACHE_DIR}"
        return
    fi
    if [[ -d /root/autodl-tmp ]]; then
        printf '%s\n' /root/autodl-tmp/.ccache
        return
    fi
    printf '%s\n' "${HOME}/.cache/ccache"
}

setup_ccache() {
    if [[ "${USE_CCACHE}" == "0" || "${USE_CCACHE}" == "false" ]]; then
        echo "ccache 已关闭（USE_CCACHE=${USE_CCACHE}）"
        return
    fi
    export USE_CCACHE=1
    if [[ -x /usr/bin/ccache ]]; then
        export CCACHE_EXEC=/usr/bin/ccache
    elif command -v ccache >/dev/null 2>&1; then
        export CCACHE_EXEC="$(command -v ccache)"
    else
        echo "警告: 找不到 ccache"
        return
    fi
    CCACHE_DIR="$(default_ccache_dir)"
    export CCACHE_DIR
    mkdir -p "${CCACHE_DIR}"
    "${CCACHE_EXEC}" -M "${CCACHE_SIZE}"
    "${CCACHE_EXEC}" -o compression=true
    echo "ccache 上限 ${CCACHE_SIZE}，目录 ${CCACHE_DIR}，已开压缩"
}

# 从 Windows 拷过来的脚本是 CRLF，Linux 会报 /usr/bin/env: ‘bash\r’
normalize_lf() {
    local f
    for f in "$@"; do
        [[ -f "${f}" ]] || continue
        sed -i 's/\r$//' "${f}"
    done
}

apply_kernel_lto() {
    local bc="${SRC_DIR}/vendor/extra/BoardConfigExtra.mk"
    case "${KERNEL_LTO}" in
        none|thin|full|"") ;;
        *) echo "KERNEL_LTO 只能是 none / thin / full / 空"; exit 1 ;;
    esac
    mkdir -p "${SRC_DIR}/vendor/extra"
    touch "${bc}"
    if grep -q '# >>> fuxi-kernel-lto' "${bc}"; then
        sed -i '/# >>> fuxi-kernel-lto/,/# <<< fuxi-kernel-lto/d' "${bc}"
    fi
    sed -i '/^KERNEL_LTO[[:space:]]*:*=/d' "${bc}"
    if [[ -n "${KERNEL_LTO}" ]]; then
        {
            echo "# >>> fuxi-kernel-lto"
            echo "KERNEL_LTO := ${KERNEL_LTO}"
            echo "# <<< fuxi-kernel-lto"
        } >> "${bc}"
        echo "内核 LTO: ${KERNEL_LTO}"
    fi
}

ensure_repo() {
    if command -v repo >/dev/null 2>&1; then
        return
    fi
    echo "==> 安装 Google repo 到 ~/bin"
    mkdir -p "${HOME}/bin"
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "${HOME}/bin/repo"
    chmod a+x "${HOME}/bin/repo"
    export PATH="${HOME}/bin:${PATH}"
}

ensure_git_identity() {
    if ! git config --global user.name >/dev/null && ! git config --local user.name >/dev/null; then
        echo "repo 需要 git 身份。先执行:"
        echo "  git config --global user.name  \"Your Name\""
        echo "  git config --global user.email \"you@example.com\""
        exit 1
    fi
    git lfs install >/dev/null 2>&1 || true
}

# LineageOS / crDroid 会自动吃 vendor/extra/{product.mk,BoardConfigExtra.mk}
# 不改官方 fuxi 设备树，repo sync 也不会冲掉。
install_miuicamera_overlay() {
    if [[ "${INCLUDE_MIUICAMERA}" != "1" ]]; then
        return
    fi
    if [[ ! -d "${OVERLAY_DIR}" ]]; then
        echo "找不到 ${OVERLAY_DIR}，把 overlays/miuicamera-fuxi 和脚本放一起"
        exit 1
    fi

    echo "==> 安装 MiuiCamera 覆盖层（不拉 Xiaomi Framework）"
    mkdir -p "${SRC_DIR}/device/xiaomi"
    rm -rf "${SRC_DIR}/device/xiaomi/miuicamera-fuxi"
    cp -a "${OVERLAY_DIR}" "${SRC_DIR}/device/xiaomi/miuicamera-fuxi"
    chmod +x "${SRC_DIR}/device/xiaomi/miuicamera-fuxi/extract-files.py" \
             "${SRC_DIR}/device/xiaomi/miuicamera-fuxi/setup-makefiles.py"
    # overlay 从 Windows 过来可能是 CRLF，sepolicy/脚本都去一下
    find "${SRC_DIR}/device/xiaomi/miuicamera-fuxi" -type f \
        \( -name '*.te' -o -name '*.mk' -o -name '*.sh' -o -name '*.py' -o -name '*.prop' \) \
        -exec sed -i 's/\r$//' {} +

    mkdir -p "${SRC_DIR}/vendor/extra"
    local extra_mk="${SRC_DIR}/vendor/extra/product.mk"
    local extra_bc="${SRC_DIR}/vendor/extra/BoardConfigExtra.mk"
    local marker="# >>> fuxi-miuicamera"

    if [[ ! -f "${extra_mk}" ]] || ! grep -q "${marker}" "${extra_mk}"; then
        {
            echo "${marker}"
            echo '$(call inherit-product-if-exists, device/xiaomi/miuicamera-fuxi/device.mk)'
            echo "# <<< fuxi-miuicamera"
        } >> "${extra_mk}"
    fi
    if [[ ! -f "${extra_bc}" ]] || ! grep -q "${marker}" "${extra_bc}"; then
        {
            echo "${marker}"
            echo '-include device/xiaomi/miuicamera-fuxi/BoardConfig.mk'
            echo "# <<< fuxi-miuicamera"
        } >> "${extra_bc}"
    fi
}

extract_miuicamera() {
    if [[ -z "${HYPEROS_ZIP}" ]]; then
        return
    fi
    if [[ ! -f "${HYPEROS_ZIP}" ]]; then
        echo "HyperOS zip 不存在: ${HYPEROS_ZIP}"
        exit 1
    fi
    echo "==> 从 ${HYPEROS_ZIP} 抽取 MiuiCamera"
    (
        cd "${SRC_DIR}/device/xiaomi/miuicamera-fuxi"
        ./extract-files.py "${HYPEROS_ZIP}"
    )
}

# 源码树已有旧 build.conf 时，只补缺失键，不改用户已经填的值。
ensure_build_conf_keys() {
    local conf="${SRC_DIR}/build.conf"
    [[ -f "${conf}" ]] || return 0
    grep -q '^KERNEL_LTO=' "${conf}" || echo 'KERNEL_LTO=thin' >> "${conf}"
    grep -q '^MAKE_JOBS=' "${conf}" || echo 'MAKE_JOBS=4' >> "${conf}"
    grep -q '^SYNC_JOBS=' "${conf}" || echo 'SYNC_JOBS=4' >> "${conf}"
    grep -q '^USE_CCACHE=' "${conf}" || echo 'USE_CCACHE=1' >> "${conf}"
    grep -q '^CCACHE_DIR=' "${conf}" || echo 'CCACHE_DIR=' >> "${conf}"
}

# Soong 只认环境变量 BUILD_USERNAME / BUILD_HOSTNAME。
# 这里写 vendor/extra + 拷一份 build-fuxi.sh，开编时导出，不跟本机 hostname。
install_build_identity() {
    mkdir -p "${SRC_DIR}/vendor/extra"
    if [[ ! -f "${SRC_DIR}/build.conf" && -f "${SCRIPT_DIR}/build.conf" ]]; then
        cp -a "${SCRIPT_DIR}/build.conf" "${SRC_DIR}/build.conf"
    fi
    ensure_build_conf_keys

    cat > "${SRC_DIR}/vendor/extra/build_info.mk" <<EOF
# 由 sync-crdroid-fuxi.sh 生成。改显示名请编辑源码树旁的 build.conf 后重跑脚本，
# 或直接改这个文件。编译必须走 build-fuxi.sh / 先 export 下面两个变量。
BUILD_USERNAME := ${BUILD_USERNAME}
BUILD_HOSTNAME := ${BUILD_HOSTNAME}
CRDROID_MAINTAINER := ${CRDROID_MAINTAINER}

PRODUCT_SYSTEM_PROPERTIES += \\
    ro.crdroid.maintainer=${CRDROID_MAINTAINER}

PRODUCT_PRODUCT_PROPERTIES += \\
    ro.crdroid.maintainer=${CRDROID_MAINTAINER}
EOF

    cat > "${SRC_DIR}/vendor/extra/env.sh" <<EOF
# source 这个再手动 breakfast：身份 + ccache。内核 LTO 在 BoardConfigExtra.mk。
export BUILD_USERNAME="${BUILD_USERNAME}"
export BUILD_HOSTNAME="${BUILD_HOSTNAME}"
export KBUILD_BUILD_USER="${BUILD_USERNAME}"
export KBUILD_BUILD_HOST="${BUILD_HOSTNAME}"
export USE_CCACHE="${USE_CCACHE}"
export CCACHE_EXEC="\${CCACHE_EXEC:-/usr/bin/ccache}"
export CCACHE_DIR="\${CCACHE_DIR:-$(default_ccache_dir)}"
EOF
    apply_kernel_lto

    local extra_mk="${SRC_DIR}/vendor/extra/product.mk"
    local marker="# >>> fuxi-build-identity"
    if [[ ! -f "${extra_mk}" ]] || ! grep -q "${marker}" "${extra_mk}"; then
        {
            echo "${marker}"
            echo '-include vendor/extra/build_info.mk'
            echo "# <<< fuxi-build-identity"
        } >> "${extra_mk}"
    fi

    if [[ -f "${SCRIPT_DIR}/build-fuxi.sh" ]]; then
        cp -a "${SCRIPT_DIR}/build-fuxi.sh" "${SRC_DIR}/build-fuxi.sh"
        chmod +x "${SRC_DIR}/build-fuxi.sh"
    fi
    normalize_lf \
        "${SRC_DIR}/build-fuxi.sh" \
        "${SRC_DIR}/build.conf" \
        "${SRC_DIR}/vendor/extra/env.sh" \
        "${SRC_DIR}/vendor/extra/product.mk" \
        "${SRC_DIR}/vendor/extra/BoardConfigExtra.mk" \
        "${SRC_DIR}/vendor/extra/build_info.mk"

    echo "编译身份: ${BUILD_USERNAME}@${BUILD_HOSTNAME}  维护者=${CRDROID_MAINTAINER}"
    setup_ccache
}

print_banner() {
    cat <<EOF

============================================================
  源码目录     : ${SRC_DIR}
  crDroid      : ${CRDROID_BRANCH}
  设备树/内核  : LineageOS ${LOS_BRANCH}
  vendor       : ${VENDOR_SOURCE}
  MiuiCamera   : ${INCLUDE_MIUICAMERA}
  编译人/机器  : ${BUILD_USERNAME}@${BUILD_HOSTNAME}
  维护者       : ${CRDROID_MAINTAINER}
  内核 LTO     : ${KERNEL_LTO:-设备树默认}
  sync -j      : ${JOBS}  （清华 AOSP 建议 4）
  make -j      : ${MAKE_JOBS}  （容器内存紧用 4）
  AOSP 镜像    : ${AOSP_MIRROR:-直连 googlesource}
  代理         : ${HTTP_PROXY:-未设置}
============================================================
  磁盘建议 >= 400GB。A16 + 内核 LTO 峰值内存很大。
  AutoDL 看的是 cgroup 限额，不是 free -h 的宿主机 251G。
  第一次 sync 要很久，中断后再跑同一条命令即可续传。
============================================================

EOF
}

# ---------- 主流程 ----------
normalize_lf \
    "${BASH_SOURCE[0]}" \
    "${SCRIPT_DIR}/build-fuxi.sh" \
    "${SCRIPT_DIR}/build.conf"
print_banner

if [[ "${INSTALL_DEPS}" == "1" ]]; then
    install_deps_ubuntu
fi

if [[ "${MANIFEST_ONLY}" == "1" ]]; then
    write_local_manifest "${SRC_DIR}/.repo/local_manifests/fuxi.xml"
    echo "只写了 manifest。之后在 ${SRC_DIR} 里 repo sync 即可。"
    exit 0
fi

need_cmd git
need_cmd curl
need_cmd python3
ensure_git_identity
setup_fetch_network
ensure_repo
need_cmd repo

mkdir -p "${SRC_DIR}"
cd "${SRC_DIR}"

if [[ "${SYNC_ONLY}" != "1" ]]; then
    if [[ ! -d .repo/manifests ]]; then
        echo "==> repo init crDroid ${CRDROID_BRANCH}"
        repo init -u https://github.com/crdroidandroid/android.git \
            -b "${CRDROID_BRANCH}" \
            --git-lfs \
            --no-clone-bundle
    else
        echo "==> 已存在 .repo，跳过 repo init（换分支请自己 repo init -b ...）"
    fi
fi

write_local_manifest "${SRC_DIR}/.repo/local_manifests/fuxi.xml"

if [[ "${SKIP_SYNC}" == "1" ]]; then
    install_miuicamera_overlay
    install_build_identity
    echo "已跳过 sync。"
    exit 0
fi

echo "==> repo sync -c --no-tags --no-clone-bundle -j${JOBS}"
repo sync -c --no-tags --no-clone-bundle --force-sync -j"${JOBS}"

install_miuicamera_overlay
install_build_identity
extract_miuicamera

if [[ -f "${SRC_DIR}/vendor/xiaomi/miuicamera-fuxi/miuicamera-fuxi-vendor.mk" ]]; then
    CAMERA_STATUS="已抽出，编译时会覆盖 Aperture"
else
    CAMERA_STATUS="设备侧已就位；还没抽 APK，这次会编 Aperture。抽完再编一次即可"
fi

cat <<EOF

============================================================
源码已经就位，可以编译 Xiaomi 13 (fuxi)。
MiuiCamera : ${CAMERA_STATUS}

  cd ${SRC_DIR}
  # Windows 上传后若报 bash\\r： sed -i 's/\\r$//' *.sh
  ./build-fuxi.sh

  # 或自己 brunch（必须先 source env，否则身份/ccache/LTO 对不上）:
  #   source vendor/extra/env.sh
  #   source build/envsetup.sh
  #   ${LUNCH_HINT}

产物一般在:
  out/target/product/fuxi/

如果还没集成进 Leica 相机，拿一份 HyperOS fuxi 官方包再跑:
  ./sync-crdroid-fuxi.sh --sync-only --hyperos-zip /path/to/fuxi-hyperos.zip
或手动:
  cd ${SRC_DIR}/device/xiaomi/miuicamera-fuxi
  ./extract-files.py /path/to/fuxi-hyperos.zip

如果 breakfast 报缺 vendor makefile:
  说明 vendor 没拉全。确认 VENDOR_SOURCE=themuppets 后重新跑本脚本，
  或进 device/xiaomi/fuxi 用真机/官方 zip 跑 ./extract-files.py
============================================================
EOF
