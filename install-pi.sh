#!/bin/sh
# ==============================================================================
#  树莓派一站式一键安装脚本  —— Netcore N30 Pro 定制 ImmortalWrt 刷机环境
#  仓库:https://github.com/markternu/openwrtnetcoren30pro
#
#  适用:刚烧好 Raspberry Pi OS( Lite )的 SD 卡,插卡上电、SSH 进去后的**第一条命令**。
#
#  用法(和 ohmyzsh 官方同款,任选其一):
#    sh -c "$(curl -fsSL https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install-pi.sh)"
#    sh -c "$(wget -qO-  https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install-pi.sh)"
#    # 国内更快(jsDelivr 镜像):
#    sh -c "$(curl -fsSL https://cdn.jsdelivr.net/gh/markternu/openwrtnetcoren30pro@main/install-pi.sh)"
#
#  它会按顺序自动完成(全部幂等,可重复运行):
#    1) 第一个安装任务:**oh-my-zsh**(装 zsh/git → 克隆 oh-my-zsh → 写 .zshrc → 换登录 shell)
#    2) 安装 **TFTP 服务**(tftpd-hpa + tcpdump,目录 /srv/tftp)
#    3) 从本仓库 **GitHub Releases 下载最新定制 OpenWrt 固件**,校验 sha256 后放进 /srv/tftp
#    4) 下载**刷机工具包**脚本到 ~/n30kit(打通救砖网络 / 收尾 / 刷后自检 / 固件下载器)
#    5) 打印下一步(只需再跑一条命令就可以按 Reset 刷机)
#
#  可选参数:
#    --no-omz          跳过 oh-my-zsh
#    --no-tftp         跳过 TFTP 服务
#    --no-firmware     跳过固件下载
#    --no-kit          跳过刷机工具包下载
#    --mirror          oh-my-zsh 走 Gitee 镜像(国内快)
#    --theme <name>    oh-my-zsh 主题(默认 robbyrussell)
#    --version vX.Y.Z  指定固件版本(默认取 latest)
#    --base-url <前缀> 固件下载镜像前缀(如 https://<镜像>/https://github.com)
#    --without-uboot   不下载换 u-boot 用的官方 FIP(默认**会**下载)
#    --dry-run         只打印将执行的动作,不改动系统
#    -h, --help        帮助
# ==============================================================================
set -e

REPO="markternu/openwrtnetcoren30pro"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
OMZ_UPSTREAM="https://github.com/ohmyzsh/ohmyzsh.git"
OMZ_MIRROR="https://gitee.com/mirrors/oh-my-zsh.git"

WITH_OMZ=yes; WITH_TFTP=yes; WITH_FIRMWARE=yes; WITH_KIT=yes; WITH_UBOOT=yes
USE_MIRROR=no; THEME="robbyrussell"; VERSION=""; BASE_URL=""; DRY_RUN=no

[ "${1:-}" = "--" ] && shift
while [ $# -gt 0 ]; do
	case "$1" in
		--no-omz)        WITH_OMZ=no ;;
		--no-tftp)       WITH_TFTP=no ;;
		--no-firmware)   WITH_FIRMWARE=no ;;
		--no-kit)        WITH_KIT=no ;;
		--without-uboot) WITH_UBOOT=no ;;
		--mirror)        USE_MIRROR=yes ;;
		--theme)         THEME="${2:-robbyrussell}"; shift ;;
		--version)       VERSION="${2:-}"; shift ;;
		--base-url)      BASE_URL="${2:-}"; shift ;;
		--dry-run)       DRY_RUN=yes ;;
		-h|--help)       sed -n '2,40p' "$0" 2>/dev/null || \
		                 printf '%s\n' "用法: sh install-pi.sh [--no-omz] [--no-tftp] [--no-firmware] [--no-kit] [--mirror] [--theme NAME] [--version vX] [--base-url URL] [--dry-run]"
		                 exit 0 ;;
		*) echo "未知参数: $1 (用 --help 查看用法)"; exit 1 ;;
	esac
	shift
done

# ------------------------------------------------------------------ 输出helpers
say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = yes ]; then say "    [dry-run] $*"; else "$@"; fi; }

# ------------------------------------------------------------------ 运行身份
# 脚本可能以普通用户(推荐)或 root 运行;oh-my-zsh 要装给"人"用的那个账号
TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$TARGET_HOME" ] || TARGET_HOME="$(eval echo "~$TARGET_USER" 2>/dev/null)"
[ -n "$TARGET_HOME" ] || TARGET_HOME="$HOME"

if [ "$(id -u)" = "0" ]; then SUDO=""
elif command -v sudo >/dev/null 2>&1; then SUDO="sudo"
else SUDO=""; warn "没有 sudo,涉及系统目录的步骤可能失败"; fi
asroot() { if [ -n "$SUDO" ]; then $SUDO "$@"; else "$@"; fi; }

# ------------------------------------------------------------------ 平台与工具
detect() {
	if [ -f /etc/openwrt_release ] || { [ -x /sbin/procd ] && [ -d /etc/config ]; }; then
		OS=openwrt
	elif [ -f /etc/debian_version ]; then OS=debian
	else OS=unknown; fi
	if command -v apt-get >/dev/null 2>&1; then PKG=apt
	elif command -v apk >/dev/null 2>&1; then PKG=apk
	elif command -v opkg >/dev/null 2>&1; then PKG=opkg
	else PKG=""; fi
	if command -v curl >/dev/null 2>&1; then DL=curl
	elif command -v wget >/dev/null 2>&1; then DL=wget
	elif command -v uclient-fetch >/dev/null 2>&1; then DL=uclient-fetch
	else DL=""; fi
}
GET_STDOUT() {
	case "$DL" in
		curl)          curl -fsSL --connect-timeout 15 "$1" ;;
		wget)          wget -q --timeout=20 -O - "$1" ;;
		uclient-fetch) uclient-fetch -q -O - "$1" ;;
		*) return 1 ;;
	esac
}
# dry-run 时只打印,不真的下载
PLAN_FETCH() {
	if [ "$DRY_RUN" = yes ]; then say "    [dry-run] 下载 $1"; return 0; fi
	GET_FILE "$1" "$2"
}
GET_FILE() {
	case "$DL" in
		curl)          curl -fL --retry 3 --connect-timeout 15 -o "$2" "$1" ;;
		wget)          wget -q --tries=3 --timeout=20 -O "$2" "$1" ;;
		uclient-fetch) uclient-fetch -q -O "$2" "$1" ;;
		*) return 1 ;;
	esac
}

PKG_PREPARED=no
pkg() {
	[ -n "$PKG" ] || { warn "未识别的包管理器,请手工安装: $*"; return 1; }
	if [ "$PKG_PREPARED" = no ]; then
		case "$PKG" in
			apt)  run apt-get update -qq >/dev/null 2>&1 || true ;;
			apk)  run apk update >/dev/null 2>&1 || true ;;
			opkg) run opkg update >/dev/null 2>&1 || true ;;
		esac
		PKG_PREPARED=yes
	fi
	case "$PKG" in
		apt)  run apt-get install -y "$@" ;;
		apk)  run apk add --no-cache "$@" ;;
		opkg) run opkg install "$@" ;;
	esac
}
pkg_each() {   # 逐个装,某个包名不存在不影响其他
	for _p in "$@"; do
		if [ "$DRY_RUN" = yes ]; then say "    [dry-run] 安装 $_p"
		elif pkg "$_p" >/dev/null 2>&1; then ok "已安装 $_p"
		else warn "安装 $_p 失败(可能源里没有,继续)"; fi
	done
}

# ================================================================ 1) oh-my-zsh
install_omz() {
	step "第 1 步/共 5 步:安装 oh-my-zsh(新系统的第一个安装任务)"

	if ! command -v zsh >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
		say "  安装依赖:zsh git"
		pkg_each zsh git
	fi
	command -v zsh >/dev/null 2>&1 || die "zsh 安装失败,请手动: sudo apt install -y zsh"
	ok "zsh: $(command -v zsh)"

	OMZ_DIR="$TARGET_HOME/.oh-my-zsh"
	if [ -d "$OMZ_DIR/.git" ]; then
		say "  已存在 $OMZ_DIR,更新中 ..."
		run git -C "$OMZ_DIR" pull --ff-only >/dev/null 2>&1 || warn "更新失败(忽略,继续用现有版本)"
	else
		REPO_URL="$OMZ_UPSTREAM"; [ "$USE_MIRROR" = yes ] && REPO_URL="$OMZ_MIRROR"
		say "  克隆 $REPO_URL"
		if ! run git clone --depth=1 "$REPO_URL" "$OMZ_DIR"; then
			if [ "$USE_MIRROR" = no ]; then
				warn "GitHub 克隆失败,自动改用 Gitee 镜像 ..."
				run git clone --depth=1 "$OMZ_MIRROR" "$OMZ_DIR"
			else
				die "克隆 oh-my-zsh 失败(检查网络后重跑)"
			fi
		fi
	fi
	[ "$DRY_RUN" = yes ] || [ -d "$OMZ_DIR" ] || die "oh-my-zsh 目录创建失败"
	ok "oh-my-zsh 就位:$OMZ_DIR"

	# .zshrc
	ZSHRC="$TARGET_HOME/.zshrc"
	[ -f "$ZSHRC" ] && run cp -f "$ZSHRC" "$ZSHRC.pre-n30pro.bak"
	if [ "$DRY_RUN" = yes ]; then
		say "    [dry-run] 写入 $ZSHRC"
	else
		cat > "$ZSHRC" <<EOF
# ~/.zshrc  (由 openwrtnetcoren30pro/install-pi.sh 生成)
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="$THEME"
plugins=(git)
source \$ZSH/oh-my-zsh.sh

alias ll='ls -lah'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'
alias gp='grep --color=auto'

# 刷机流程快捷命令
alias n30kit='cd ~/n30kit'
alias n30net='sudo ~/n30kit/pi-net-on.sh'
alias n30tftp='sudo tcpdump -i eth0 -n -e udp port 69'
EOF
		chown "$TARGET_USER" "$ZSHRC" 2>/dev/null || true
		ok "已写入 $ZSHRC(原文件备份为 .zshrc.pre-n30pro.bak)"
	fi

	# 切换登录 shell
	ZSH_BIN="$(command -v zsh || echo /usr/bin/zsh)"
	if [ "$DRY_RUN" = yes ]; then
		say "    [dry-run] chsh -s $ZSH_BIN $TARGET_USER"
	elif command -v chsh >/dev/null 2>&1; then
		asroot chsh -s "$ZSH_BIN" "$TARGET_USER" 2>/dev/null && ok "登录 shell 已设为 $ZSH_BIN" \
			|| warn "chsh 失败,可手动: chsh -s $ZSH_BIN"
	fi
}

# ================================================================ 2) TFTP 服务
install_tftp() {
	step "第 2 步/共 5 步:安装 TFTP 服务"
	pkg_each tftpd-hpa tcpdump curl ca-certificates
	run asroot mkdir -p /srv/tftp
	run asroot chmod 755 /srv/tftp
	if [ "$DRY_RUN" = yes ]; then
		say "    [dry-run] 写 /etc/default/tftpd-hpa 并重启服务"
	else
		printf '%s\n' \
			'TFTP_USERNAME="tftp"' \
			'TFTP_DIRECTORY="/srv/tftp"' \
			'TFTP_ADDRESS="0.0.0.0:69"' \
			'TFTP_OPTIONS="--secure --create"' \
			| asroot tee /etc/default/tftpd-hpa >/dev/null
		asroot systemctl restart tftpd-hpa 2>/dev/null \
			|| asroot service tftpd-hpa restart 2>/dev/null \
			|| warn "服务重启失败,请检查: systemctl status tftpd-hpa"
		ok "TFTP 服务就绪:/srv/tftp (0.0.0.0:69)"
	fi
}

# ================================================================ 3) 下载固件
fetch_firmware() {
	step "第 3 步/共 5 步:从 GitHub Releases 下载定制 OpenWrt 固件"

	[ -n "$DL" ] || die "没有可用下载器(curl/wget)"

	if [ -z "$VERSION" ] && [ "$DRY_RUN" = yes ]; then
		VERSION="v1.0.0"
		say "  (dry-run 跳过网络查询,按 $VERSION 演示)"
	elif [ -z "$VERSION" ]; then
		say "  查询最新版本 ..."
		VERSION="$(GET_STDOUT "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
			| grep -o '"tag_name"[^,]*' | head -1 | sed 's/.*"tag_name" *: *"//; s/"$//')" || true
		[ -n "$VERSION" ] || { VERSION="v1.0.0"; warn "API 不可用,回落 $VERSION"; }
	fi
	ok "版本:$VERSION"

	REL="${BASE_URL}https://github.com/$REPO/releases/download/$VERSION"
	DEST="/tmp/n30pro-firmware"
	run mkdir -p "$DEST"

	say "  下载 SHA256SUMS 与固件(共约 26MB) ..."
	PLAN_FETCH "$REL/SHA256SUMS" "$DEST/SHA256SUMS" || die "下载 SHA256SUMS 失败"
	for f in immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb \
	         immortalwrt-mediatek-filogic-netis_nx30v2-initramfs.itb; do
		say "    - $f"
		PLAN_FETCH "$REL/$f" "$DEST/$f" || die "下载 $f 失败"
	done

	say "  校验 sha256 ..."
	if [ "$DRY_RUN" = yes ]; then
		say "    [dry-run] sha256sum -c"
	else
		( cd "$DEST" && grep -E "netis_nx30v2-(squashfs-sysupgrade|initramfs)\.itb" SHA256SUMS > .check \
			&& sha256sum -c .check && rm -f .check ) \
			|| die "固件校验失败!删除 $DEST 后重跑,或用 --base-url 换镜像"
		ok "固件校验通过"
	fi

	# 可选:换 u-boot 用的官方 FIP
	if [ "$WITH_UBOOT" = yes ]; then
		say "  下载官方 u-boot FIP(换 u-boot 时用,可选) ..."
		UB="https://downloads.immortalwrt.org/releases/25.12.0/targets/mediatek/filogic"
		FIP="immortalwrt-25.12.0-mediatek-filogic-netis_nx30v2-spim-nand-bl31-uboot.fip"
		if PLAN_FETCH "$UB/sha256sums" "$DEST/sha256sums-iwrt" 2>/dev/null \
		   && PLAN_FETCH "$UB/$FIP" "$DEST/$FIP"; then
			if [ "$DRY_RUN" = no ]; then
				( cd "$DEST" && grep " $FIP\$" sha256sums-iwrt > .ub && sha256sum -c .ub && rm -f .ub ) \
					&& ok "u-boot FIP 校验通过" || warn "u-boot FIP 校验未通过,请手工核对"
			fi
		else
			warn "u-boot 下载失败(不影响刷固件;需要时手工下载)"
		fi
	fi

	# 放进 TFTP 目录
	if [ "$DRY_RUN" = yes ]; then
		say "    [dry-run] cp $DEST/*.itb /srv/tftp/"
	else
		asroot mkdir -p /srv/tftp
		asroot cp -f "$DEST"/immortalwrt-mediatek-filogic-netis_nx30v2-*.itb /srv/tftp/
		asroot chown root:root /srv/tftp/*.itb 2>/dev/null || true
		asroot chmod 644 /srv/tftp/*.itb 2>/dev/null || true
		asroot systemctl restart tftpd-hpa 2>/dev/null || true
		ok "已放入 /srv/tftp:"
		ls -la /srv/tftp/*.itb 2>/dev/null | awk '{printf "      %s  %s\n",$5,$9}'
	fi
}

# ================================================================ 4) 刷机工具包
fetch_kit() {
	step "第 4 步/共 5 步:下载刷机工具包到 $TARGET_HOME/n30kit"
	KIT="$TARGET_HOME/n30kit"
	run mkdir -p "$KIT"
	for f in pi-net-on.sh pi-net-off.sh verify-after-boot.sh pi-fetch-firmware.sh pi-setup-tftp.sh; do
		say "    - $f"
		PLAN_FETCH "$RAW_BASE/flash-kit/$f" "$KIT/$f" || warn "下载 $f 失败"
	done
	if [ "$DRY_RUN" = no ]; then
		chmod +x "$KIT"/*.sh 2>/dev/null || true
		chown -R "$TARGET_USER" "$KIT" 2>/dev/null || true
		ok "工具包就位:$KIT"
	fi
}

# ================================================================ 5) 总结
summary() {
	step "第 5 步/共 5 步:完成 ✅  树莓派已就绪"
	say "  目录:"
	say "    固件     : /srv/tftp/"
	say "    工具脚本 : $TARGET_HOME/n30kit/"
	say "    oh-my-zsh: $TARGET_HOME/.oh-my-zsh"
	say ""
	say "  下一步(只剩两件事):"
	say "    1) 用网线把树莓派 eth0 接到路由器的 LAN 口"
	say "    2) 执行(会临时改网络,Mac 请继续用 WiFi 的 IP SSH):"
	say "         sudo $TARGET_HOME/n30kit/pi-net-on.sh"
	say "       然后另开一个窗口抓包:"
	say "         sudo tcpdump -i eth0 -n -e udp port 69"
	say "       路由器:断电 → 按住 Reset → 上电 10 秒 → 松开"
	say ""
	say "  完整图文步骤(含换 u-boot / 从原厂系统开始):"
	say "    https://github.com/$REPO/blob/main/docs/%E5%96%82%E9%A5%AD%E6%95%99%E7%A8%8B-%E4%BB%8E%E9%9B%B6%E5%88%B0%E4%B8%8A%E7%BD%91%28%E6%A0%91%E8%8E%93%E6%B4%BE%2B%E5%8E%9F%E5%8E%82%E8%B7%AF%E7%94%B1%E5%99%A8%29.md"
	say ""
	say "  提示:重跑本脚本可随时补装/更新;想换 shell 立刻生效请执行: exec zsh"
}

# ================================================================ main
main() {
	detect
	step "环境识别"
	say "  系统      : $OS"
	say "  包管理器  : ${PKG:-未知}"
	say "  下载器    : ${DL:-未知}"
	say "  目标用户  : $TARGET_USER ($TARGET_HOME)"
	[ "$DRY_RUN" = yes ] && warn "dry-run 模式:只打印,不改动任何东西"

	if [ "$OS" = openwrt ]; then
		die "这台机器看起来是 OpenWrt 路由器,不是树莓派。路由器请用: install.sh(oh-my-zsh)/ install-extras.sh(其他安装)"
	fi
	if [ "$OS" = unknown ] && [ "$DRY_RUN" = no ]; then
		die "未识别的系统(本脚本面向 Raspberry Pi OS / Debian)。要预览流程可加 --dry-run"
	fi

	[ "$WITH_OMZ" = yes ]      && install_omz
	[ "$WITH_TFTP" = yes ]     && install_tftp
	[ "$WITH_FIRMWARE" = yes ] && fetch_firmware
	[ "$WITH_KIT" = yes ]      && fetch_kit
	summary
}

main
