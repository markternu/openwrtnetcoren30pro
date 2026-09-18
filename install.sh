#!/bin/sh
# ==============================================================================
#  Netcore N30 Pro 定制 ImmortalWrt · 一键安装脚本
#  仓库:https://github.com/markternu/openwrtnetcoren30pro
#
#  默认行为(也是"刷完新系统后的第一个安装任务"):安装 oh-my-zsh
#
#  用法(和 ohmyzsh 同款,任选其一):
#    sh -c "$(curl -fsSL https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install.sh)"
#    sh -c "$(wget -qO- https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install.sh)"
#    # OpenWrt 固件没带 curl/wget 时(只带 uclient-fetch),用这条零依赖的:
#    sh -c "$(uclient-fetch -O - https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install.sh)"
#
#  可选参数:
#    --with-flash-kit     另外下载刷机工具包到 ~/n30kit(树莓派用)
#    --with-tftp          另外装好 TFTP 服务并建 /srv/tftp(树莓派用)
#    --with-firmware      另外下载最新固件并放进 /srv/tftp(树莓派用,隐含 --with-flash-kit)
#    --mirror             克隆 oh-my-zsh 走 Gitee 镜像(国内网络快)
#    --theme <name>       指定 oh-my-zsh 主题(默认 robbyrussell)
#    --uninstall          卸载 oh-my-zsh 并还原 .zshrc / 登录 shell
#    --dry-run            只打印将要执行的动作,不真正改动系统
#    -h, --help           显示帮助
# ==============================================================================
set -e

REPO="markternu/openwrtnetcoren30pro"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
OMZ_UPSTREAM="https://github.com/ohmyzsh/ohmyzsh.git"
OMZ_MIRROR="https://gitee.com/mirrors/oh-my-zsh.git"

WITH_FLASHKIT=no
WITH_TFTP=no
WITH_FIRMWARE=no
USE_MIRROR=no
UNINSTALL=no
DRY_RUN=no
THEME="robbyrussell"

# ---------------------------------------------------------------- 参数解析
# 兼容: sh -c "$(curl ...)" -- --with-flash-kit   (此时 $1 是 "--")
[ "${1:-}" = "--" ] && shift
while [ $# -gt 0 ]; do
	case "$1" in
		--with-flash-kit) WITH_FLASHKIT=yes ;;
		--with-tftp)      WITH_TFTP=yes ;;
		--with-firmware)  WITH_FIRMWARE=yes; WITH_FLASHKIT=yes ;;
		--mirror)         USE_MIRROR=yes ;;
		--theme)          THEME="${2:-robbyrussell}"; shift ;;
		--uninstall)      UNINSTALL=yes ;;
		--dry-run)        DRY_RUN=yes ;;
		-h|--help)        sed -n '2,32p' "$0" 2>/dev/null || \
		                  printf '%s\n' "用法: sh install.sh [--mirror] [--theme NAME] [--with-flash-kit] [--with-tftp] [--with-firmware] [--uninstall] [--dry-run]"; exit 0 ;;
		*) echo "未知参数: $1 (用 --help 查看用法)"; exit 1 ;;
	esac
	shift
done

# ---------------------------------------------------------------- 小工具
say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = yes ]; then say "    [dry-run] $*"; else "$@"; fi; }

# ---------------------------------------------------------------- 平台识别
detect_os() {
	if [ -f /etc/openwrt_release ] || { [ -x /sbin/procd ] && [ -d /etc/config ]; }; then
		OS=openwrt
	elif [ -f /etc/debian_version ]; then
		OS=debian
	elif [ "$(uname -s)" = "Darwin" ]; then
		OS=macos
	else
		OS=unknown
	fi
}

PKG=""
detect_pkg() {
	if command -v apk >/dev/null 2>&1; then PKG=apk
	elif command -v opkg >/dev/null 2>&1; then PKG=opkg
	elif command -v apt-get >/dev/null 2>&1; then PKG=apt
	else PKG=""; fi
}

# 安装系统包(自动适配 apk / opkg / apt)
pkg_install() {
	[ -n "$PKG" ] || { warn "未识别的包管理器,请手工安装: $*"; return 1; }
	case "$PKG" in
		apk)  run apk update >/dev/null 2>&1 || true
		      run apk add --no-cache "$@" ;;
		opkg) run opkg update >/dev/null 2>&1 || true
		      run opkg install "$@" ;;
		apt)  run apt-get update -qq >/dev/null 2>&1 || true
		      run apt-get install -y "$@" ;;
	esac
}

# 下载器:curl > wget > uclient-fetch(OpenWrt 一定自带)
DL=""
detect_downloader() {
	if command -v curl >/dev/null 2>&1; then DL=curl
	elif command -v wget >/dev/null 2>&1; then DL=wget
	elif command -v uclient-fetch >/dev/null 2>&1; then DL=uclient-fetch
	else DL=""; fi
}
fetch_to_stdout() {
	case "$DL" in
		curl)          curl -fsSL "$1" ;;
		wget)          wget -qO- "$1" ;;
		uclient-fetch) uclient-fetch -q -O - "$1" ;;
		*) return 1 ;;
	esac
}
fetch_to_file() {
	case "$DL" in
		curl)          curl -fL --retry 3 -o "$2" "$1" ;;
		wget)          wget -q --tries=3 -O "$2" "$1" ;;
		uclient-fetch) uclient-fetch -q -O "$2" "$1" ;;
		*) return 1 ;;
	esac
}

# ---------------------------------------------------------------- oh-my-zsh
OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"
ZSHRC="$HOME/.zshrc"

uninstall_omz() {
	step "卸载 oh-my-zsh"
	[ -d "$OMZ_DIR" ] && run rm -rf "$OMZ_DIR" && ok "已删除 $OMZ_DIR" || warn "$OMZ_DIR 不存在"
	if [ -f "$ZSHRC.pre-n30pro.bak" ]; then
		run mv -f "$ZSHRC.pre-n30pro.bak" "$ZSHRC"; ok "已还原 .zshrc"
	else
		[ -f "$ZSHRC" ] && run rm -f "$ZSHRC" && ok "已删除 .zshrc"
	fi
	case "$OS" in
		openwrt)
			run sed -i "s|^root:\(.*\):[^:]*$|root:\1:/bin/ash|" /etc/passwd 2>/dev/null || true
			ok "root 登录 shell 已还原为 /bin/ash" ;;
		debian)
			run chsh -s /bin/bash "$(id -un)" 2>/dev/null || true
			ok "登录 shell 已还原为 /bin/bash" ;;
	esac
	say ""
	say "卸载完成(用 'exec bash' 或重新登录生效)。"
}

write_zshrc() {
	[ -f "$ZSHRC" ] && run cp -f "$ZSHRC" "$ZSHRC.pre-n30pro.bak"
	if [ "$DRY_RUN" = yes ]; then say "    [dry-run] 写入 $ZSHRC"; return 0; fi
	cat > "$ZSHRC" <<EOF
# ~/.zshrc  (由 openwrtnetcoren30pro/install.sh 生成)
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="$THEME"
plugins=(git)
source \$ZSH/oh-my-zsh.sh

# ---- 常用别名 ----
alias ll='ls -lah'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'

# ---- 本项目相关 ----
alias usbfix='usb-fix-check'
alias fwver='grep DISTRIB_REVISION /etc/openwrt_release'
alias kmods='apk info 2>/dev/null | grep -i "^kmod" | sort'
EOF
	ok "已写入 $ZSHRC(原文件备份为 .zshrc.pre-n30pro.bak)"
}

set_login_shell() {
	ZSH_BIN="$(command -v zsh || echo /usr/bin/zsh)"
	case "$OS" in
		openwrt)
			# OpenWrt 没有 chsh,直接改 /etc/passwd
			if grep -q "^root:.*:${ZSH_BIN}$" /etc/passwd 2>/dev/null; then
				ok "root 登录 shell 已是 $ZSH_BIN"
			else
				run sed -i "s|^root:\(.*\):[^:]*$|root:\1:${ZSH_BIN}|" /etc/passwd
				ok "root 登录 shell 已设为 $ZSH_BIN(已运行中的会话用 'exec zsh' 立即切换)"
			fi ;;
		debian)
			run chsh -s "$ZSH_BIN" "$(id -un)" 2>/dev/null || warn "chsh 失败,可手工执行: chsh -s $ZSH_BIN"
			ok "登录 shell 已设为 $ZSH_BIN" ;;
		*)
			warn "未识别的系统,请手工把登录 shell 设为 $ZSH_BIN" ;;
	esac
}

install_ohmyzsh() {
	step "第 1 步:安装 oh-my-zsh(刷完新系统的第一个安装任务)"

	# 1) 依赖:先装关键项(zsh/git),再装可选证书与 https 支持
	if ! command -v zsh >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
		say "  安装依赖:zsh git"
		pkg_install zsh git || true
	fi
	case "$OS" in
		openwrt) pkg_install ca-bundle ca-certificates git-http || true ;;
		debian)  pkg_install curl ca-certificates || true ;;
	esac
	command -v zsh >/dev/null 2>&1 || die "zsh 安装失败。请先手工安装 zsh(apk add zsh / apt install zsh)后重跑"
	ok "zsh: $(command -v zsh)"

	# 2) 拉取 oh-my-zsh
	REPO_URL="$OMZ_UPSTREAM"
	[ "$USE_MIRROR" = yes ] && REPO_URL="$OMZ_MIRROR"
	if [ -d "$OMZ_DIR/.git" ]; then
		say "  已存在 $OMZ_DIR,执行更新 ..."
		run git -C "$OMZ_DIR" pull --ff-only >/dev/null 2>&1 || warn "更新失败(可忽略,继续用现有版本)"
	elif command -v git >/dev/null 2>&1; then
		say "  克隆 $REPO_URL -> $OMZ_DIR"
		run git clone --depth=1 "$REPO_URL" "$OMZ_DIR" || {
			if [ "$USE_MIRROR" = no ]; then
				warn "GitHub 克隆失败,自动改用 Gitee 镜像重试 ..."
				run git clone --depth=1 "$OMZ_MIRROR" "$OMZ_DIR"
			else
				die "克隆 oh-my-zsh 失败(检查网络,或稍后重试)"
			fi
		}
	else
		warn "没有 git,改用压缩包方式安装(无法使用 'omz update')"
		TMPTG="$(mktemp -d)"
		fetch_to_file "https://codeload.github.com/ohmyzsh/ohmyzsh/tar.gz/refs/heads/master" "$TMPTG/omz.tar.gz" \
			|| die "下载 oh-my-zsh 压缩包失败"
		run mkdir -p "$OMZ_DIR"
		run tar -xzf "$TMPTG/omz.tar.gz" -C "$OMZ_DIR" --strip-components=1
		run rm -rf "$TMPTG"
	fi
	[ "$DRY_RUN" = yes ] || [ -d "$OMZ_DIR" ] || die "oh-my-zsh 目录创建失败"
	ok "oh-my-zsh 就位: $OMZ_DIR"

	# 3) 写 .zshrc
	write_zshrc

	# 4) 切换登录 shell
	set_login_shell

	step "oh-my-zsh 安装完成 🎉"
	say "  立即体验:  exec zsh"
	say "  想换主题:  编辑 ~/.zshrc 里的 ZSH_THEME,或重跑本脚本加 --theme agnoster"
	say "  卸载:      sh install.sh --uninstall"
}

# ---------------------------------------------------------------- 树莓派附加项
KIT_DIR="$HOME/n30kit"
with_flashkit() {
	step "下载刷机工具包到 $KIT_DIR"
	[ -n "$DL" ] || die "没有可用的下载器(curl / wget / uclient-fetch)"
	run mkdir -p "$KIT_DIR"
	for f in pi-setup-tftp.sh pi-fetch-firmware.sh pi-net-on.sh pi-net-off.sh verify-after-boot.sh; do
		say "  - $f"
		fetch_to_file "$RAW_BASE/flash-kit/$f" "$KIT_DIR/$f" || warn "下载 $f 失败"
	done
	run chmod +x "$KIT_DIR"/*.sh 2>/dev/null || true
	ok "工具包就位:$KIT_DIR"
}

with_tftp() {
	step "安装并配置 TFTP 服务"
	pkg_install tftpd-hpa tcpdump curl || true
	run mkdir -p /srv/tftp
	run chmod 755 /srv/tftp
	if [ "$DRY_RUN" = no ] && [ -d /etc/default ]; then
		cat > /etc/default/tftpd-hpa <<'EOF'
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure --create"
EOF
	fi
	run systemctl restart tftpd-hpa 2>/dev/null || run service tftpd-hpa restart 2>/dev/null || true
	ok "TFTP 服务已配置(目录 /srv/tftp)"
}

with_firmware() {
	step "下载最新固件并放进 /srv/tftp"
	if [ -x "$KIT_DIR/pi-fetch-firmware.sh" ]; then
		if [ "$DRY_RUN" = yes ]; then say "    [dry-run] sh $KIT_DIR/pi-fetch-firmware.sh --install"
		else
			SUDO=""; [ "$(id -u)" != "0" ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo
			$SUDO sh "$KIT_DIR/pi-fetch-firmware.sh" --install
		fi
	else
		warn "缺少 $KIT_DIR/pi-fetch-firmware.sh,请先加 --with-flash-kit"
	fi
}

# ---------------------------------------------------------------- 主流程
main() {
	detect_os
	detect_pkg
	detect_downloader

	step "环境识别"
	say "  系统:     $OS"
	say "  包管理器: ${PKG:-未知}"
	say "  下载器:   ${DL:-未知}"
	[ "$DRY_RUN" = yes ] && warn "dry-run 模式:只打印,不改动"

	if [ "$UNINSTALL" = yes ]; then
		uninstall_omz
		return 0
	fi

	install_ohmyzsh

	[ "$WITH_FLASHKIT" = yes ] && with_flashkit
	[ "$WITH_TFTP"     = yes ] && with_tftp
	[ "$WITH_FIRMWARE" = yes ] && with_firmware

	step "全部完成"
	say "  下一步建议:"
	say "    - 路由器:  exec zsh  → 然后去 LuCI 开 WiFi / 配 F50 上网"
	say "    - 树莓派:  sudo sh ~/n30kit/pi-net-on.sh  → 开始刷机流程"
	say "  文档: https://github.com/$REPO"
}

main
