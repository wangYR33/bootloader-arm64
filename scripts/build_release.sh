#!/bin/bash
#
# build_release.sh - 一条命令完成 编包 -> 解包 -> chroot 定制 -> 重新打包
#
# 默认流程(不带参数): revert + customize + pack
#   revert    : revert_sdcard_package sdcard.tgz  -> sdcard_out/
#   customize : chroot sdcard_out/rootfs 装包/禁服务/改密码
#   pack      : rebuild_sdcard_package sdcard_out -> sdcard_out/sdcard.tgz
#
# 定制内容改 build_release.conf 即可(与本脚本同目录), 不用动脚本本体。
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP_DIR="${TOP_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

# ---------------------------------------------------------------- 默认定制项
APT_PACKAGES=(mosquitto alsa-utils ntp)
APT_OPTS="-y"
DISABLE_SERVICES=(nginx sophliteos getty@tty1 ntp)
MASK_SERVICES=(getty@tty1)
ENABLE_SERVICES=()
ROOT_PASSWORD="aselsan"
TARGET_DNS=(8.8.8.8)
TARGET_DNS_SEARCH=()
BUILD_DNS=()
PKG_TYPES=(sdcard)
TGZ_NAME="sdcard.tgz"

[ -f "$SCRIPT_DIR/build_release.conf" ] && source "$SCRIPT_DIR/build_release.conf"

# ---------------------------------------------------------------- 日志
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
log()  { echo "${CYN}[*]${RST} $*"; }
ok()   { echo "${GRN}[+]${RST} $*"; }
warn() { echo "${YEL}[!]${RST} $*" >&2; }
die()  { echo "${RED}[x]${RST} $*" >&2; exit 1; }

usage() {
    cat <<EOF
用法: $(basename "$0") [选项]

阶段(可任意组合, 不指定 = -r -c -p):
  -b, --build       执行 build_edge_rootfs 重新编译整包(耗时最久)
                    注意: 该阶段会 rm -rf 整个 package_edge, 包括已有的
                    sdcard_out。同一 SDK 树同时只允许跑一个实例(已加 flock)。
  -r, --revert      解包 \$OUTPUT_DIR/package_edge/$TGZ_NAME
  -c, --customize   chroot 定制(装包 / 禁服务 / 改 root 密码)
  -p, --pack        重新打包成 sdcard.tgz
  -a, --all         等价于 -b -r -c -p

其他:
  -s, --shell       定制完成后进入 chroot 交互 shell(手工排查用)
  -t, --type TYPE   打包类型, 逗号分隔, 默认 ${PKG_TYPES[*]} (可选 sdcard,usb,tftp)
  -d, --dir DIR     指定 package_edge 目录(默认由 SDK 环境自动推导)
  -n, --dry-run     只打印将要执行的定制动作, 不改动任何文件
  -h, --help        显示本帮助

示例:
  $(basename "$0")              # 已有 sdcard.tgz, 走 解包->定制->打包
  $(basename "$0") -a           # 改了 overlay/deb, 从编译开始全跑
  $(basename "$0") -c -p        # 上次解包结果还在, 只重做定制和打包
  $(basename "$0") -c -s        # 定制后进 chroot 手工确认
  $(basename "$0") -a -t sdcard,usb
EOF
}

# ---------------------------------------------------------------- 参数解析
DO_BUILD=0; DO_REVERT=0; DO_CUSTOM=0; DO_PACK=0; DO_SHELL=0; DRY_RUN=0
PKG_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        -b|--build)     DO_BUILD=1 ;;
        -r|--revert)    DO_REVERT=1 ;;
        -c|--customize) DO_CUSTOM=1 ;;
        -p|--pack)      DO_PACK=1 ;;
        -a|--all)       DO_BUILD=1; DO_REVERT=1; DO_CUSTOM=1; DO_PACK=1 ;;
        -s|--shell)     DO_SHELL=1 ;;
        -n|--dry-run)   DRY_RUN=1 ;;
        -t|--type)      IFS=, read -r -a PKG_TYPES <<< "${2:?-t 需要参数}"; shift ;;
        -d|--dir)       PKG_DIR="${2:?-d 需要参数}"; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              die "未知参数: $1 (-h 看用法)" ;;
    esac
    shift
done

# 未指定任何阶段 -> 默认三步
if [ $((DO_BUILD + DO_REVERT + DO_CUSTOM + DO_PACK)) -eq 0 ]; then
    DO_REVERT=1; DO_CUSTOM=1; DO_PACK=1
fi

# ---------------------------------------------------------------- 互斥锁
# 必须独占: -b 阶段的 build_package() 会 `sudo rm -rf $OUTPUT_DIR/package_edge`
# (envsetup_soc.sh:1271), 连同别人正在用的 sdcard_out 一起删掉。两个实例并行
# 会互相削, 表现为打包时莫名其妙的 "xxx.N-of-M: No such file or directory"。
LOCK_FILE="$TOP_DIR/.build_release.lock"
exec 9>>"$LOCK_FILE"
if ! flock -n 9; then
    die "已有另一个 $(basename "$0") 在跑 (PID $(head -1 "$LOCK_FILE" 2>/dev/null || echo '?'))
    并行执行会互相破坏 package_edge, 请等它结束。锁文件: $LOCK_FILE"
fi
: >"$LOCK_FILE"
printf '%s\n' "$$" >&9

# ---------------------------------------------------------------- SDK 环境
# envsetup_soc.sh / common_functions.sh 顶层带 return, 直接在函数里 source 会被
# 提前打断, 所以统一丢到子 shell 里跑。olddefconfig 复用现有 build/.config,
# 不会覆盖你的配置, 只是把 OUTPUT_DIR / CVIARCH / BOARD 等变量重新导出。
SDK_PRELUDE='source build/envsetup_soc.sh >/dev/null 2>&1; olddefconfig >/dev/null 2>&1;'

# sdk_run <shell命令> : 在带 SDK 环境的子 shell 里执行, 输出直通
sdk_run() {
    ( cd "$TOP_DIR" && bash -c "$SDK_PRELUDE $1" )
}

load_sdk_env() {
    [ -f "$TOP_DIR/build/envsetup_soc.sh" ] || die "找不到 $TOP_DIR/build/envsetup_soc.sh"
    log "加载 SDK 环境 (TOP_DIR=$TOP_DIR)"

    local info
    info=$(sdk_run 'type revert_sdcard_package >/dev/null 2>&1 || exit 3
                    printf "%s\n%s\n%s\n" "$OUTPUT_DIR" "$BOARD" "$CVIARCH"')
    case $? in
        3) die "revert_sdcard_package 未定义, 请先在 SDK 根目录执行 ./install.sh 打补丁" ;;
        0) ;;
        *) die "SDK 环境加载失败" ;;
    esac

    { read -r SDK_OUTPUT_DIR; read -r SDK_BOARD; read -r SDK_CVIARCH; } <<< "$info"
    [ -n "$SDK_OUTPUT_DIR" ] || \
        die "OUTPUT_DIR 为空, 请先手工跑一次 'source build/envsetup_soc.sh && defconfig <board>'"
    ok "OUTPUT_DIR=$SDK_OUTPUT_DIR  BOARD=$SDK_BOARD  CVIARCH=$SDK_CVIARCH"
}

load_sdk_env
PKG_DIR="${PKG_DIR:-$SDK_OUTPUT_DIR/package_edge}"
OUT_DIR="$PKG_DIR/${TGZ_NAME%.tgz}_out"
ROOTFS="$OUT_DIR/rootfs"

# ---------------------------------------------------------------- chroot 管理
MOUNTED=()

chroot_umount() {
    local i
    for (( i=${#MOUNTED[@]}-1 ; i>=0 ; i-- )); do
        sudo umount -l "${MOUNTED[i]}" 2>/dev/null
    done
    MOUNTED=()
    # 还原 resolv.conf / policy-rc.d
    if [ -n "${ROOTFS:-}" ] && [ -d "$ROOTFS" ]; then
        sudo rm -f "$ROOTFS/usr/sbin/policy-rc.d"
        if [ -e "$ROOTFS/etc/resolv.conf.bak-release" ]; then
            sudo mv -f "$ROOTFS/etc/resolv.conf.bak-release" "$ROOTFS/etc/resolv.conf"
        fi
    fi
}
trap chroot_umount EXIT INT TERM

chroot_mount() {
    local r="$1" m
    for m in proc sys dev dev/pts; do
        sudo mkdir -p "$r/$m"
    done
    sudo mount -t proc  proc "$r/proc"    && MOUNTED+=("$r/proc")
    sudo mount -t sysfs sys  "$r/sys"     && MOUNTED+=("$r/sys")
    sudo mount --bind /dev      "$r/dev"     && MOUNTED+=("$r/dev")
    sudo mount --bind /dev/pts  "$r/dev/pts" && MOUNTED+=("$r/dev/pts")

    # apt 需要 DNS; 原文件(常为 systemd-resolved 软链)先备份, 退出时还原。
    # 这里写的是"构建期"DNS, 与镜像里的设备 DNS 无关, 退出时会被还原掉。
    if [ -e "$r/etc/resolv.conf" ] || [ -L "$r/etc/resolv.conf" ]; then
        sudo mv -f "$r/etc/resolv.conf" "$r/etc/resolv.conf.bak-release"
    fi
    if [ ${#BUILD_DNS[@]} -gt 0 ]; then
        log "  chroot 内使用 BUILD_DNS: ${BUILD_DNS[*]}"
        printf 'nameserver %s\n' "${BUILD_DNS[@]}" | sudo tee "$r/etc/resolv.conf" >/dev/null
    else
        # chroot 与宿主共享网络命名空间, 所以宿主的 127.0.0.x 解析器
        # (Docker 的 127.0.0.11 / systemd-resolved 的 127.0.0.53) 在 chroot 内
        # 同样可用, 直接照搬即可。只有压根没有 nameserver 才是真的坏了。
        if ! grep -qE '^[[:space:]]*nameserver[[:space:]]' /etc/resolv.conf 2>/dev/null; then
            warn "宿主机 /etc/resolv.conf 里没有任何 nameserver, chroot 内 apt 会解析失败"
            warn "请在 build_release.conf 里设置 BUILD_DNS=(<真实DNS>)"
        fi
        sudo cp -f /etc/resolv.conf "$r/etc/resolv.conf"
    fi

    # chroot 内禁止 apt 拉起 daemon(否则 mosquitto/ntp 安装会卡住或报错)
    printf '#!/bin/sh\nexit 101\n' | sudo tee "$r/usr/sbin/policy-rc.d" >/dev/null
    sudo chmod +x "$r/usr/sbin/policy-rc.d"
}

# ---------------------------------------------------------------- 设备 DNS
# 写进镜像, 设备开机后生效。纯文件改写, 不需要 chroot。
# 本镜像 renderer=networkd + 静态 IP, DNS 实际来自 netplan 各网口的
# nameservers.addresses; resolved.conf 的全局 DNS= 只在网口没给 DNS 时兜底,
# 所以两处都写, 才能保证真正生效。
apply_target_dns() {
    local r="$1"
    if [ ${#TARGET_DNS[@]} -eq 0 ]; then
        log "  TARGET_DNS 为空, 保持镜像原有 DNS 配置不变"
        return 0
    fi

    local list spaced tmp y n
    list=$(IFS=,; echo "${TARGET_DNS[*]}")    # 8.8.8.8,1.1.1.1
    spaced="${TARGET_DNS[*]}"                 # 8.8.8.8 1.1.1.1

    # 1) netplan —— 只替换 nameservers: 紧跟的那一行 addresses:, 缩进和其余内容原样保留
    shopt -s nullglob
    for y in "$r"/etc/netplan/*.yaml "$r"/etc/netplan/*.yml; do
        grep -qE '^[[:space:]]*nameservers:' "$y" || continue
        tmp=$(mktemp)
        awk -v dns="$list" '
            /^[[:space:]]*nameservers:[[:space:]]*$/ { print; inns=1; next }
            inns && /^[[:space:]]*addresses:/ {
                match($0, /^[[:space:]]*/)
                print substr($0, 1, RLENGTH) "addresses: [" dns "]"
                inns=0; next
            }
            { inns=0; print }
        ' "$y" > "$tmp"
        n=$(grep -cE "^[[:space:]]*addresses: \[$list\]$" "$tmp")
        if cmp -s "$y" "$tmp"; then
            ok "  netplan $(basename "$y"): 已是 [$list], 无需改动"
        else
            sudo cp -f "$tmp" "$y"
            ok "  netplan $(basename "$y"): $n 处 nameservers -> [$list]"
        fi
        rm -f "$tmp"
    done
    shopt -u nullglob

    # 2) resolved.conf 全局兜底
    local rc_file="$r/etc/systemd/resolved.conf"
    if [ -f "$rc_file" ]; then
        tmp=$(mktemp)
        # 先删掉已生效的 DNS=/Domains=(注释行保留, 留作文档)
        sed -E '/^[[:space:]]*(DNS|Domains)=/d' "$rc_file" > "$tmp"
        if grep -q '^\[Resolve\]' "$tmp"; then
            sed -i "/^\[Resolve\]/a DNS=$spaced" "$tmp"
        else
            printf '\n[Resolve]\nDNS=%s\n' "$spaced" >> "$tmp"
        fi
        if [ ${#TARGET_DNS_SEARCH[@]} -gt 0 ]; then
            sed -i "/^DNS=/a Domains=${TARGET_DNS_SEARCH[*]}" "$tmp"
        fi
        sudo cp -f "$tmp" "$rc_file"
        rm -f "$tmp"
        ok "  resolved.conf: DNS=$spaced${TARGET_DNS_SEARCH[*]:+ Domains=${TARGET_DNS_SEARCH[*]}}"
    else
        warn "  找不到 $rc_file, 跳过全局 DNS"
    fi
}

# ---------------------------------------------------------------- 阶段实现
stage_build() {
    log "阶段 1/4: build_edge_rootfs"
    sdk_run 'build_edge_rootfs' || die "build_edge_rootfs 失败"
    ok "编译完成"
}

stage_revert() {
    log "阶段 2/4: 解包 $TGZ_NAME"
    [ -f "$PKG_DIR/$TGZ_NAME" ] || die "找不到 $PKG_DIR/$TGZ_NAME (先跑 -b ?)"
    sdk_run "cd '$PKG_DIR' && revert_sdcard_package './$TGZ_NAME'" || die "revert_sdcard_package 失败"
    [ -d "$ROOTFS" ] || die "解包后没有 $ROOTFS"
    ok "已解包到 $OUT_DIR"
}

stage_customize() {
    log "阶段 3/4: chroot 定制 $ROOTFS"
    [ -d "$ROOTFS" ] || die "找不到 $ROOTFS (先跑 -r ?)"

    echo "    安装软件包 : ${APT_PACKAGES[*]:-<无>}"
    echo "    禁用服务   : ${DISABLE_SERVICES[*]:-<无>}"
    echo "    屏蔽服务   : ${MASK_SERVICES[*]:-<无>}"
    echo "    启用服务   : ${ENABLE_SERVICES[*]:-<无>}"
    echo "    root 密码  : $ROOT_PASSWORD"
    echo "    设备 DNS   : ${TARGET_DNS[*]:-<不改动>}${TARGET_DNS_SEARCH[*]:+  搜索域: ${TARGET_DNS_SEARCH[*]}}"
    echo "    构建期 DNS : ${BUILD_DNS[*]:-<沿用宿主机 resolv.conf>}"
    if [ "$DRY_RUN" = 1 ]; then
        warn "dry-run, 跳过实际执行"
        return 0
    fi

    chroot_mount "$ROOTFS"

    sudo chroot "$ROOTFS" /bin/bash <<CHROOT_EOF
set -u
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

rc=0

if [ -n "${APT_PACKAGES[*]:-}" ]; then
    echo ">>> apt-get update"
    apt-get update || { echo "apt-get update 失败(无网络?)"; rc=1; }
    echo ">>> apt-get install ${APT_PACKAGES[*]}"
    apt-get install $APT_OPTS ${APT_PACKAGES[*]} || rc=1
    apt-get clean
    rm -rf /var/lib/apt/lists/*
fi

run_systemctl() {   # \$1=动作 \$2=服务名
    local out
    if out=\$(systemctl "\$1" "\$2" 2>&1); then
        [ -n "\$out" ] && echo "\$out" | sed 's/^/    /'
        return 0
    fi
    echo "\$out" | sed 's/^/    /'
    echo "    ${YEL}(跳过: \$2 不存在或无法 \$1)${RST}"
    return 1
}

for svc in ${DISABLE_SERVICES[*]:-}; do
    echo ">>> systemctl disable \$svc"
    run_systemctl disable "\$svc"
done

# mask 用于 getty@tty1 这类由 generator 动态生成的单元 —— 只 disable 无效,
# systemd-getty-generator 每次启动都会重新拉起, 必须 mask 成 /dev/null。
for svc in ${MASK_SERVICES[*]:-}; do
    echo ">>> systemctl mask \$svc"
    run_systemctl mask "\$svc"
done

for svc in ${ENABLE_SERVICES[*]:-}; do
    echo ">>> systemctl enable \$svc"
    run_systemctl enable "\$svc"
done

echo ">>> 设置 root 密码"
echo "root:$ROOT_PASSWORD" | chpasswd || rc=1

exit \$rc
CHROOT_EOF
    local rc=$?

    log "  写入设备 DNS"
    apply_target_dns "$ROOTFS"

    if [ $DO_SHELL = 1 ]; then
        log "进入 chroot 交互 shell, exit 退出"
        sudo chroot "$ROOTFS" /bin/bash -i
    fi

    chroot_umount
    [ $rc -eq 0 ] || die "chroot 定制存在失败项(见上方输出)"
    ok "定制完成"
}

stage_pack() {
    log "阶段 4/4: 重新打包 [${PKG_TYPES[*]}]"
    [ -d "$OUT_DIR" ] || die "找不到 $OUT_DIR (先跑 -r ?)"
    # 确保没有残留挂载被打进包里
    chroot_umount

    local t
    for t in "${PKG_TYPES[@]}"; do
        log "  -> rebuild_sdcard_package $OUT_DIR $t"
        sdk_run "rebuild_sdcard_package '$OUT_DIR' '$t'" || die "rebuild_sdcard_package $t 失败"
        ok "  $OUT_DIR/$t.tgz"
    done
}

# ---------------------------------------------------------------- 主流程
START=$SECONDS
[ $DO_BUILD  = 1 ] && stage_build
[ $DO_REVERT = 1 ] && stage_revert
[ $DO_CUSTOM = 1 ] && stage_customize
[ $DO_PACK   = 1 ] && stage_pack

ok "全部完成, 耗时 $(( (SECONDS-START)/60 ))m$(( (SECONDS-START)%60 ))s"
[ $DO_PACK = 1 ] && echo "    产物: $OUT_DIR/${PKG_TYPES[0]}.tgz"
exit 0
