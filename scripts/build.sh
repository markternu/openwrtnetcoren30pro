#!/bin/bash
# ============================================================
# 一键复现编译(Netcore N30 Pro 定制 ImmortalWrt)
#
# 用法:
#   ./scripts/build.sh /path/to/immortalwrt [jobs]
#
# 前置:
#   - Linux 主机 / 大小写敏感文件系统(Linux,或 macOS 上的 Linux 虚拟机)
#   - 依赖:build-essential clang flex bison gawk gettext git libncurses5-dev \
#           libssl-dev python3 rsync swig unzip zlib1g-dev file wget curl
#
# 说明:
#   本脚本固化了几处"不这么做就编不过/编出来不可用"的坑,详见 docs/复现编译说明.md
# ============================================================
set -e

SRC="${1:?用法: $0 /path/to/immortalwrt [jobs]}"
JOBS="${2:-$(nproc)}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

cd "$SRC"

echo "== 1/6 应用补丁"
"$HERE/scripts/apply-patches.sh" "$SRC"

echo "== 2/6 生成最小 .config"
cat > .config <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_netcore_n30pro=y
CONFIG_TARGET_PER_DEVICE_ROOTFS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
EOF

echo "== 3/6 feeds(只装 luci;其余 feed 未使用)"
./scripts/feeds update luci
./scripts/feeds install -a -p luci

echo "== 4/6 make defconfig + 强制打开默认不选的内核模块"
make defconfig
# 这几个 kmod 的 Kconfig 符号默认是 DEFAULT:=m if ALL_KMODS,defconfig 不会选中它们,
# 这也是官方仓库里找不到这些包的原因。必须显式写进 .config。
for s in kmod-tun kmod-nft-tproxy kmod-nft-socket kmod-nf-tproxy kmod-nf-socket \
         kmod-inet-diag kmod-netlink-diag; do
	if grep -qE "^CONFIG_PACKAGE_${s}=" .config; then
		sed -i "s|^CONFIG_PACKAGE_${s}=.*|CONFIG_PACKAGE_${s}=y|" .config
	else
		echo "CONFIG_PACKAGE_${s}=y" >> .config
	fi
done
# 编译期修补:该 fork 用 apk 打包,base-files 的 ipk 风格版本号(含 ~)会被 apk 拒绝
grep -q "VERSION:=\$(PKG_RELEASE)-r1" package/base-files/Makefile || {
	sed -i 's|VERSION:=\$(PKG_RELEASE)~.*|VERSION:=$(PKG_RELEASE)-r1|' package/base-files/Makefile
	sed -i 's|echo \$(PKG_RELEASE)~.*>|echo $(PKG_RELEASE)-r1 >|' package/base-files/Makefile
}
# 避免编译一整套 host LLVM(与 USB/代理功能无关,且极易 OOM)
sed -i 's|^CONFIG_USE_LLVM_BUILD=y|# CONFIG_USE_LLVM_BUILD is not set|' .config
# 关掉依赖 bpf-headers(需 clang)的 bridger;它依赖的内核模块与代理功能无关
sed -i 's|^CONFIG_PACKAGE_bridger=y|# CONFIG_PACKAGE_bridger is not set|' .config
sed -i 's|^CONFIG_HAS_BPF_TOOLCHAIN=y|# CONFIG_HAS_BPF_TOOLCHAIN is not set|' .config
sed -i 's|^CONFIG_NEED_BPF_TOOLCHAIN=y|# CONFIG_NEED_BPF_TOOLCHAIN is not set|' .config
# 源码无 .git 时版本号会回落成 unknown,被 apk 拒绝;显式给一个合法 revision
echo 'CONFIG_VERSION_CODE="r37877-n30pro"' >> .config

echo "== 5/6 编译(首次含工具链+内核,耗时长)"
make -j"$JOBS" V=s REVISION=r37877-n30pro

echo "== 6/6 产物"
ls -la bin/targets/mediatek/filogic/*.itb
sha256sum bin/targets/mediatek/filogic/immortalwrt-mediatek-filogic-netcore_n30pro-squashfs-sysupgrade.itb
