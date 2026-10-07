#!/usr/bin/env bash
# 读 build.conf 开编：编译人 / 机器名 / 内核 LTO / ccache / -j。
# 用法:
#   ./build-fuxi.sh
#   ./build-fuxi.sh user
#   SRC_DIR=/root/autodl-tmp/crd ./build-fuxi.sh userdebug
#
# 不要对整份脚本 set -u/-e：envsetup.sh 不兼容，会看起来像“跑完 lunch 就退出”。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 脚本若已在源码树里，不要误用 ~/android/crdroid
if [[ -z "${SRC_DIR:-}" ]]; then
    if [[ -f "${SCRIPT_DIR}/build/envsetup.sh" ]]; then
        SRC_DIR="${SCRIPT_DIR}"
    else
        SRC_DIR="${HOME}/android/crdroid"
    fi
fi
VARIANT="${1:-userdebug}"

load_conf() {
    local f
    for f in "${SRC_DIR}/build.conf" "${SCRIPT_DIR}/build.conf"; do
        if [[ -f "${f}" ]]; then
            # shellcheck disable=SC1090
            source "${f}"
            echo "已读取 ${f}"
            return
        fi
    done
}

# 空则：AutoDL 数据盘，否则 ~/.cache/ccache
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

# 写 vendor/extra/BoardConfigExtra.mk 的 KERNEL_LTO。改值就清 KERNEL_OBJ。
apply_kernel_lto() {
    local bc="${SRC_DIR}/vendor/extra/BoardConfigExtra.mk"
    local stamp="${SRC_DIR}/out/.fuxi_kernel_lto"
    local prev="" want="${KERNEL_LTO:-}"

    case "${want}" in
        none|thin|full|"") ;;
        *)
            echo "KERNEL_LTO 只能是 none / thin / full / 空，现在是: ${want}"
            return 1 2>/dev/null || exit 1
            ;;
    esac

    mkdir -p "${SRC_DIR}/vendor/extra"
    touch "${bc}"
    if grep -q '# >>> fuxi-kernel-lto' "${bc}"; then
        sed -i '/# >>> fuxi-kernel-lto/,/# <<< fuxi-kernel-lto/d' "${bc}"
    fi
    sed -i '/^KERNEL_LTO[[:space:]]*:*=/d' "${bc}"

    if [[ -n "${want}" ]]; then
        {
            echo "# >>> fuxi-kernel-lto"
            echo "KERNEL_LTO := ${want}"
            echo "# <<< fuxi-kernel-lto"
        } >> "${bc}"
        echo "内核 LTO : ${want}  (${bc})"
    else
        echo "内核 LTO : 设备树默认"
    fi

    if [[ -f "${stamp}" ]]; then
        prev="$(cat "${stamp}")"
    fi
    if [[ "${prev}" != "${want}" ]]; then
        if [[ -d "${SRC_DIR}/out/target/product/fuxi/obj/KERNEL_OBJ" ]]; then
            echo "KERNEL_LTO ${prev:-<default>} -> ${want:-<default>}，清除 KERNEL_OBJ"
            rm -rf "${SRC_DIR}/out/target/product/fuxi/obj/KERNEL_OBJ"
        fi
        mkdir -p "${SRC_DIR}/out"
        printf '%s\n' "${want}" > "${stamp}"
    fi
}

setup_ccache() {
    USE_CCACHE="${USE_CCACHE:-1}"
    if [[ "${USE_CCACHE}" == "0" || "${USE_CCACHE}" == "false" ]]; then
        unset USE_CCACHE CCACHE_EXEC
        echo "ccache   : 关闭"
        return
    fi
    export USE_CCACHE=1
    if [[ -x /usr/bin/ccache ]]; then
        export CCACHE_EXEC="${CCACHE_EXEC:-/usr/bin/ccache}"
    elif command -v ccache >/dev/null 2>&1; then
        export CCACHE_EXEC="$(command -v ccache)"
    else
        echo "警告: 找不到 ccache，这次不会走缓存"
        return
    fi
    export CCACHE_DIR
    CCACHE_DIR="$(default_ccache_dir)"
    mkdir -p "${CCACHE_DIR}"
    "${CCACHE_EXEC}" -M "${CCACHE_SIZE:-20G}" >/dev/null || true
    "${CCACHE_EXEC}" -o compression=true >/dev/null || true
    echo "ccache   : ${CCACHE_EXEC}"
    echo "缓存目录 : ${CCACHE_DIR}  上限 ${CCACHE_SIZE:-20G}"
    echo "查统计   : CCACHE_DIR=${CCACHE_DIR} ccache -s"
}

load_conf

BUILD_USERNAME="${BUILD_USERNAME:-crdroid}"
BUILD_HOSTNAME="${BUILD_HOSTNAME:-fuxi}"
CRDROID_MAINTAINER="${CRDROID_MAINTAINER:-${BUILD_USERNAME}}"
CCACHE_SIZE="${CCACHE_SIZE:-20G}"
MAKE_JOBS="${MAKE_JOBS:-${JOBS:-4}}"
# 未写 KERNEL_LTO 时默认 thin；conf 里写成空则跟设备树默认
if [[ -z "${KERNEL_LTO+x}" ]]; then
    KERNEL_LTO=thin
fi

export BUILD_USERNAME
export BUILD_HOSTNAME
export KBUILD_BUILD_USER="${BUILD_USERNAME}"
export KBUILD_BUILD_HOST="${BUILD_HOSTNAME}"

if [[ ! -f "${SRC_DIR}/build/envsetup.sh" ]]; then
    echo "找不到 ${SRC_DIR}/build/envsetup.sh，先跑 sync-crdroid-fuxi.sh"
    exit 1
fi

cd "${SRC_DIR}" || exit 1

echo "编译人  : ${BUILD_USERNAME}"
echo "机器名  : ${BUILD_HOSTNAME}"
echo "维护者  : ${CRDROID_MAINTAINER}"
echo "lunch   : lineage_fuxi / ${VARIANT}"
echo "make -j : ${MAKE_JOBS}"

apply_kernel_lto || exit 1
setup_ccache

echo "==> source build/envsetup.sh"
# shellcheck disable=SC1091
source build/envsetup.sh

if ! type breakfast >/dev/null 2>&1; then
    echo "envsetup.sh 没有提供 breakfast，source 可能失败了"
    return 1 2>/dev/null || exit 1
fi

echo "==> breakfast fuxi ${VARIANT}"
breakfast fuxi "${VARIANT}" || {
    echo "breakfast 失败"
    return 1 2>/dev/null || exit 1
}

echo "==> mka bacon -j${MAKE_JOBS}"
mka bacon -j"${MAKE_JOBS}" || {
    echo "mka bacon 失败"
    echo "若只有 'action cancelled when ninja exited'：不是源码错误，查 dmesg / df / cgroup 内存。"
    return 1 2>/dev/null || exit 1
}
