#!/bin/sh
# ============================================================
# 树莓派:直接从本项目的 GitHub Releases 下载固件并校验
#          (仓库是公开的,不需要登录、不需要 gh 命令)
#
# 用法:
#   sudo sh pi-fetch-firmware.sh                 # 下载到 /tmp/n30pro-firmware
#   sudo sh pi-fetch-firmware.sh --install       # 下载并直接放进 /srv/tftp(推荐)
#   sudo sh pi-fetch-firmware.sh --with-uboot    # 顺便下载换 u-boot 用的官方 FIP
#   sudo sh pi-fetch-firmware.sh --version v1.0.0
#   sudo sh pi-fetch-firmware.sh --base-url https://<镜像前缀>/github.com/...
#
# 说明:
#   * 默认取 "latest" release;取不到就回落到 v1.0.0
#   * 会用 release 里的 SHA256SUMS 自动校验,不会下到坏文件
#   * 只需树莓派此刻能上外网(装 tftpd 时它本来就是通的)
# ============================================================
set -e

REPO="markternu/openwrtnetcoren30pro"
DEFAULT_VERSION="v1.0.0"
DEST="/tmp/n30pro-firmware"
INSTALL=no
WITH_UBOOT=no
VERSION=""
BASE_URL=""          # 形如 https://ghproxy.example.com/https://github.com   (可选镜像前缀)
UBOOT_URL="https://downloads.immortalwrt.org/releases/25.12.0/targets/mediatek/filogic"
UBOOT_FILE="immortalwrt-25.12.0-mediatek-filogic-netis_nx30v2-spim-nand-bl31-uboot.fip"

while [ $# -gt 0 ]; do
	case "$1" in
		--install)      INSTALL=yes ;;
		--with-uboot)   WITH_UBOOT=yes ;;
		--version)      VERSION="$2"; shift ;;
		--base-url)     BASE_URL="$2"; shift ;;
		--dest)         DEST="$2"; shift ;;
		-h|--help)      sed -n '2,20p' "$0"; exit 0 ;;
		*) echo "未知参数: $1(用 --help 看用法)"; exit 1 ;;
	esac
	shift
done

# ---------- 下载工具探测 ----------
if command -v curl >/dev/null 2>&1; then
	FETCH() { curl -fL --retry 3 --connect-timeout 15 -o "$2" "$1"; }
	GET()   { curl -fsL --retry 3 --connect-timeout 15 "$1"; }
elif command -v wget >/dev/null 2>&1; then
	FETCH() { wget -q --tries=3 --timeout=20 -O "$2" "$1"; }
	GET()   { wget -q --tries=3 --timeout=20 -O - "$1"; }
else
	echo "缺少 curl 或 wget,请先: sudo apt install -y curl"; exit 1
fi

# ---------- 确定版本 ----------
if [ -z "$VERSION" ]; then
	echo "==> 查询最新 release ..."
	VERSION="$(GET "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
		| grep -o '"tag_name"[^,]*' | head -1 | sed 's/.*"tag_name" *: *"//; s/"$//')" || true
	[ -n "$VERSION" ] || { VERSION="$DEFAULT_VERSION"; echo "    (API 不可用,回落到 $VERSION)"; }
fi
echo "==> 版本: $VERSION"

REL_BASE="${BASE_URL}https://github.com/$REPO/releases/download/$VERSION"
mkdir -p "$DEST"

echo "==> 下载 SHA256SUMS"
FETCH "$REL_BASE/SHA256SUMS" "$DEST/SHA256SUMS"

echo "==> 下载固件(约 26MB,慢的话耐心等)"
for f in \
	immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb \
	immortalwrt-mediatek-filogic-netis_nx30v2-initramfs.itb
do
	echo "    - $f"
	FETCH "$REL_BASE/$f" "$DEST/$f"
done

echo "==> 校验 sha256"
( cd "$DEST" && grep -E "netis_nx30v2-(squashfs-sysupgrade|initramfs)\.itb" SHA256SUMS > .check \
	&& sha256sum -c .check && rm -f .check ) || {
	echo
	echo "❌ 校验失败!可能是下载不完整。删掉 $DEST 里的文件重跑,或换网络/加 --base-url 用镜像。"
	exit 1
}

# ---------- 可选:官方 u-boot(换 u-boot 用) ----------
if [ "$WITH_UBOOT" = "yes" ]; then
	echo "==> 下载官方 u-boot FIP(换 u-boot 用)"
	if GET "$UBOOT_URL/sha256sums" > "$DEST/sha256sums-immortalwrt" 2>/dev/null; then
		FETCH "$UBOOT_URL/$UBOOT_FILE" "$DEST/$UBOOT_FILE"
		( cd "$DEST" && grep " $UBOOT_FILE\$" sha256sums-immortalwrt > .ubcheck \
			&& sha256sum -c .ubcheck && rm -f .ubcheck ) \
			|| echo "⚠️  u-boot 校验未通过(官方 sha256sums 里没找到或下载不全),请手工核对"
	else
		echo "⚠️  取不到官方 sha256sums,直接下载(请自行核对来源)"
		FETCH "$UBOOT_URL/$UBOOT_FILE" "$DEST/$UBOOT_FILE"
	fi
fi

# ---------- 放进 TFTP 目录 ----------
if [ "$INSTALL" = "yes" ]; then
	[ "$(id -u)" = "0" ] || { echo "❌ --install 需要 sudo"; exit 1; }
	echo "==> 安装到 /srv/tftp"
	mkdir -p /srv/tftp && chmod 755 /srv/tftp
	cp -f "$DEST"/immortalwrt-mediatek-filogic-netis_nx30v2-*.itb /srv/tftp/
	chown root:root /srv/tftp/*.itb 2>/dev/null || true
	chmod 644 /srv/tftp/*.itb 2>/dev/null || true
	systemctl restart tftpd-hpa 2>/dev/null || true
	echo
	echo "--- /srv/tftp 现状 ---"
	ls -la /srv/tftp/
fi

echo
echo "================ 结果 ================"
echo "下载目录: $DEST"
ls -la "$DEST"/*.itb 2>/dev/null | awk '{print "  "$5"  "$9}'
echo
echo "下一步:"
echo "  1) 让固件就位(若没用 --install):"
echo "       sudo cp $DEST/immortalwrt-mediatek-filogic-netis_nx30v2-*.itb /srv/tftp/"
echo "  2) 打开救砖网络:  sudo sh pi-net-on.sh"
echo "  3) 抓包看请求:    sudo tcpdump -i eth0 -n -e udp port 69"
echo "======================================"
