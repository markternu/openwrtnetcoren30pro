#!/bin/bash
# ============================================================
# 在 ImmortalWrt/OpenWrt 源码树上应用本项目的全部补丁
#
# 用法:
#   ./scripts/apply-patches.sh /path/to/immortalwrt
#   (默认源码基线:SamZong233/immortalwrt commit 3c71dfc2b6,内核 6.12)
# ============================================================
set -e

SRC="${1:-.}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

[ -d "$SRC/target/linux/mediatek" ] || { echo "错误: $SRC 看起来不是 ImmortalWrt/OpenWrt 源码树"; exit 1; }

echo "== 源码树: $SRC"
echo "== 补丁集: $HERE/patches"

# 1) 设备树(直接用最终文件覆盖,最稳)
cp -f "$HERE/patches/target-dts-mt7981b-netcore-n30pro.dts" \
      "$SRC/target/linux/mediatek/dts/mt7981b-netcore-n30pro.dts"
echo "[ok] DTS: USB VBUS(GPIO23 regulator)+ vbus-supply -> target/linux/mediatek/dts/mt7981b-netcore-n30pro.dts"

# 2) 设备包列表(DEVICE_PACKAGES:USB 网络共享驱动 + luci + 代理内核模块 + usbfix)
#    注意:每个补丁的上下文行号可能与你的源码略有偏移,失败时用 patch -p1 手工确认
apply_p1() {
	local f="$1" desc="$2"
	if patch -p1 --dry-run -s -i "$f" >/dev/null 2>&1; then
		patch -p1 -s -i "$f" && echo "[ok] $desc"
	else
		echo "[skip] $desc (补丁无法干净应用,请手工对照 $f)"
	fi
}

apply_p1 "$HERE/patches/target-image-filogic.mk.patch"        "filogic.mk: DEVICE_PACKAGES"
apply_p1 "$HERE/patches/upgrade-platform.sh.patch"            "platform.sh: netcore,n30pro 走 fit_do_upgrade(根因修复)"
apply_p1 "$HERE/patches/board.d-02_network.patch"             "02_network: netcore,n30pro 的 LAN/WAN 默认映射"
apply_p1 "$HERE/patches/build-base-files-apk-version.patch"   "base-files: apk 合法版本号(编译期修补)"

# 3) 本地包:usbfix(自检脚本)
if [ -d "$SRC/package/utils" ]; then
	rm -rf "$SRC/package/utils/usbfix"
	cp -R "$HERE/packages/usbfix" "$SRC/package/utils/usbfix"
	echo "[ok] 本地包: package/utils/usbfix(提供 /usr/sbin/usb-fix-check)"
fi

# 4) cgi-io(luci-base 依赖,取自 immortalwrt/packages,避免克隆整个 packages feed)
if [ ! -d "$SRC/package/net/cgi-io" ]; then
	mkdir -p "$SRC/package/net/cgi-io"
	cp -f "$HERE/patches/build-cgi-io-Makefile.txt" "$SRC/package/net/cgi-io/Makefile"
	echo "[ok] 本地包: package/net/cgi-io"
fi

echo
echo "完成。接下来按 docs/复现编译说明.md 配置 .config 并编译。"
