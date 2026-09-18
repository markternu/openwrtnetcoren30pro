#!/bin/sh
# ==============================================================================
#  Netcore N30 Pro 定制 ImmortalWrt · 第二任务:一键安装"其他"
#  (第一任务是 oh-my-zsh:见 install.sh)
#
#  用法(和 ohmyzsh 同款,任选其一):
#    sh -c "$(curl -fsSL https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install-extras.sh)"
#    sh -c "$(wget -qO- https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install-extras.sh)"
#    # OpenWrt 只带 uclient-fetch 时:
#    sh -c "$(uclient-fetch -O - https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install-extras.sh)"
#
#  路由器(OpenWrt)可选参数:
#    --with-proxy      安装 OpenClash + PassWall(含中文包)
#    --with-openclash  只装 OpenClash
#    --with-passwall   只装 PassWall
#    --with-ttyd       安装网页终端 ttyd(便于手机/浏览器操作)
#    --with-tools      安装常用工具(nano htop curl ca-bundle),默认已包含
#    (不带任何参数 = 装常用工具 + 打印后续步骤)
#
#  树莓派(Debian)可选参数:
#    --with-flash-kit  下载刷机工具包到 ~/n30kit
#    --with-tftp       装好 TFTP 服务并建 /srv/tftp
#    --with-firmware   下载最新固件放进 /srv/tftp(隐含 --with-flash-kit)
#    (树莓派不带参数 = 只做体检与环境确认)
#
#  通用:
#    --dry-run         只打印,不改动
#    -h, --help        帮助
# ==============================================================================
set -e

REPO="markternu/openwrtnetcoren30pro"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

WITH_PROXY=no; WITH_OPENCLASH=no; WITH_PASSWALL=no; WITH_TTYD=no; WITH_TOOLS=no
WITH_FLASHKIT=no; WITH_TFTP=no; WITH_FIRMWARE=no
DRY_RUN=no

[ "${1:-}" = "--" ] && shift
while [ $# -gt 0 ]; do
	case "$1" in
		--with-proxy)     WITH_PROXY=yes ;;
		--with-openclash) WITH_OPENCLASH=yes ;;
		--with-passwall)  WITH_PASSWALL=yes ;;
		--with-ttyd)      WITH_TTYD=yes ;;
		--with-tools)     WITH_TOOLS=yes ;;
		--with-flash-kit) WITH_FLASHKIT=yes ;;
		--with-tftp)      WITH_TFTP=yes ;;
		--with-firmware)  WITH_FIRMWARE=yes; WITH_FLASHKIT=yes ;;
		--dry-run)        DRY_RUN=yes ;;
		-h|--help)        sed -n '2,34p' "$0" 2>/dev/null || \
		                  printf '%s\n' "用法: sh install-extras.sh [--with-proxy|--with-openclash|--with-passwall|--with-ttyd|--with-tools|--with-flash-kit|--with-tftp|--with-firmware] [--dry-run]"; exit 0 ;;
		*) echo "未知参数: $1 (用 --help 查看用法)"; exit 1 ;;
	esac
	shift
done

say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = yes ]; then say "    [dry-run] $*"; else "$@"; fi; }

# 提权封装:root 直接跑,普通用户走 sudo
if [ "$(id -u)" = "0" ]; then SUDO=""
elif command -v sudo >/dev/null 2>&1; then SUDO="sudo"
else SUDO=""; fi
asroot() { if [ -n "$SUDO" ]; then $SUDO "$@"; else "$@"; fi; }

detect() {
	if [ -f /etc/openwrt_release ] || { [ -x /sbin/procd ] && [ -d /etc/config ]; }; then OS=openwrt
	elif [ -f /etc/debian_version ]; then OS=debian
	else OS=unknown; fi
	PKG_PREPARED=no
	if command -v apk >/dev/null 2>&1; then PKG=apk
	elif command -v opkg >/dev/null 2>&1; then PKG=opkg
	elif command -v apt-get >/dev/null 2>&1; then PKG=apt
	else PKG=""; fi
	if command -v curl >/dev/null 2>&1; then DL=curl
	elif command -v wget >/dev/null 2>&1; then DL=wget
	elif command -v uclient-fetch >/dev/null 2>&1; then DL=uclient-fetch
	else DL=""; fi
}

pkg_each() {
	for _p in "$@"; do
		pkg "$_p" >/dev/null 2>&1 && ok "已安装 $_p" || warn "安装 $_p 失败(可忽略)"
	done
}

pkg() {
	[ -n "$PKG" ] || { warn "未识别的包管理器,请手工安装: $*"; return 1; }
	if [ "$PKG_PREPARED" = no ]; then
		case "$PKG" in
			apk)  run asroot apk update >/dev/null 2>&1 || true ;;
			opkg) run asroot opkg update >/dev/null 2>&1 || true ;;
			apt)  run asroot apt-get update -qq >/dev/null 2>&1 || true ;;
		esac
		PKG_PREPARED=yes
	fi
	case "$PKG" in
		apk)  run asroot apk add --no-cache "$@" ;;
		opkg) run asroot opkg install "$@" ;;
		apt)  run asroot apt-get install -y "$@" ;;
	esac
}

fetch_file() {
	case "$DL" in
		curl)          curl -fL --retry 3 -o "$2" "$1" ;;
		wget)          wget -q --tries=3 -O "$2" "$1" ;;
		uclient-fetch) uclient-fetch -q -O "$2" "$1" ;;
		*) return 1 ;;
	esac
}

KIT_DIR="$HOME/n30kit"

openwrt_extras() {
	if [ "$WITH_TOOLS" = yes ] || [ "$WITH_PROXY" = no ] && [ "$WITH_OPENCLASH" = no ] && [ "$WITH_PASSWALL" = no ] && [ "$WITH_TTYD" = no ]; then
		step "安装常用工具"
		pkg_each curl ca-bundle nano htop
		ok "常用工具处理完成"
	fi

	if [ "$WITH_TTYD" = yes ]; then
		step "安装网页终端 ttyd"
		pkg_each ttyd
		[ "$DRY_RUN" = no ] && { asroot /etc/init.d/ttyd enable 2>/dev/null || true; asroot /etc/init.d/ttyd start 2>/dev/null || true; }
		ok "ttyd:http://192.168.1.1:7681"
	fi

	[ "$WITH_PROXY" = yes ] && { WITH_OPENCLASH=yes; WITH_PASSWALL=yes; }

	if [ "$WITH_OPENCLASH" = yes ]; then
		step "安装 OpenClash"
		pkg_each luci-app-openclash
	fi
	if [ "$WITH_PASSWALL" = yes ]; then
		step "安装 PassWall(含中文包)"
		pkg_each luci-app-passwall luci-i18n-passwall-zh-cn
	fi

	step "环境自检"
	if command -v usb-fix-check >/dev/null 2>&1; then
		run usb-fix-check || true
	else
		warn "未找到 usb-fix-check(可能不是本项目固件)"
	fi

	step "路由器后续步骤(在 LuCI 里点几下)"
	say "  1. 网络 → 无线:启用 radio0/radio1 并填 WiFi 名称/密码"
	say "  2. 网络 → 接口 → WAN:设备改成 F50 的 usb0 / eth2,协议 DHCP"
	say "  3. 服务 → OpenClash / PassWall:启用并选 TUN/TPROXY 模式"
}

debian_extras() {
	step "树莓派环境确认"
	say "  zsh: $(command -v zsh || echo '未安装(先跑 install.sh)')"
	say "  下载器: ${DL:-无}"

	if [ "$WITH_FLASHKIT" = yes ]; then
		step "下载刷机工具包到 $KIT_DIR"
		[ -n "$DL" ] || die "没有可用下载器"
		run mkdir -p "$KIT_DIR"
		for f in pi-setup-tftp.sh pi-fetch-firmware.sh pi-net-on.sh pi-net-off.sh verify-after-boot.sh; do
			say "  - $f"
			if [ "$DRY_RUN" = yes ]; then say "    [dry-run] 下载 $RAW_BASE/flash-kit/$f"
			else fetch_file "$RAW_BASE/flash-kit/$f" "$KIT_DIR/$f" || warn "下载 $f 失败"; fi
		done
		run chmod +x "$KIT_DIR"/*.sh 2>/dev/null || true
		ok "工具包就位:$KIT_DIR"
	fi

	if [ "$WITH_TFTP" = yes ]; then
		step "安装并配置 TFTP 服务"
		pkg_each tftpd-hpa tcpdump curl
		run asroot mkdir -p /srv/tftp && run asroot chmod 755 /srv/tftp
		if [ "$DRY_RUN" = no ] && [ -d /etc/default ]; then
			cat > /etc/default/tftpd-hpa <<'EOF'
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure --create"
EOF
		fi
		run asroot systemctl restart tftpd-hpa 2>/dev/null || run asroot service tftpd-hpa restart 2>/dev/null || true
		ok "TFTP 服务已配置(/srv/tftp)"
	fi

	if [ "$WITH_FIRMWARE" = yes ]; then
		step "下载最新固件到 /srv/tftp"
		if [ -x "$KIT_DIR/pi-fetch-firmware.sh" ]; then
			SUDO=""; [ "$(id -u)" != "0" ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo
			if [ "$DRY_RUN" = yes ]; then say "    [dry-run] $SUDO sh $KIT_DIR/pi-fetch-firmware.sh --install"
			else $SUDO sh "$KIT_DIR/pi-fetch-firmware.sh" --install; fi
		else
			warn "缺少 $KIT_DIR/pi-fetch-firmware.sh,请加上 --with-flash-kit"
		fi
	fi

	if [ "$WITH_FLASHKIT" = no ] && [ "$WITH_TFTP" = no ] && [ "$WITH_FIRMWARE" = no ]; then
		say ""
		say "  想一键准备刷机环境,重跑时加参数:"
		say "    --with-flash-kit --with-tftp --with-firmware"
	fi
}

main() {
	detect
	step "环境识别"
	say "  系统:     $OS"
	say "  包管理器: ${PKG:-未知}"
	say "  下载器:   ${DL:-未知}"
	[ "$DRY_RUN" = yes ] && warn "dry-run 模式:只打印,不改动"

	case "$OS" in
		openwrt) openwrt_extras ;;
		debian)  debian_extras ;;
		*) die "未识别的系统(本脚本面向 OpenWrt 路由器或树莓派/Debian)" ;;
	esac

	step "完成"
	say "  文档: https://github.com/$REPO"
}

main
