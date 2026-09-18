#!/bin/sh
# ============================================================
# 在【树莓派】上运行:准备 TFTP 服务器(不改网络配置)
#
# 用法:
#   sudo sh pi-setup-tftp.sh                     # 只装服务(推荐:配合 pi-fetch-firmware.sh 下载固件)
#   sudo sh pi-setup-tftp.sh <固件.itb> [...]     # 同时把本地固件放进 /srv/tftp 并校验
#
# 组合用法(树莓派能上外网,最省事):
#   sudo sh pi-setup-tftp.sh
#   sudo sh pi-fetch-firmware.sh --install       # 直接从本项目 GitHub Releases 下载+校验+就位
#
# 注意:apt 需要网络,请在树莓派【还能上网】时执行(还没动 eth0 静态 IP 的时候)
# ============================================================
set -e

if [ "$(id -u)" != "0" ]; then
	echo "请用 sudo 运行: sudo sh $0 [固件.itb ...]"
	exit 1
fi

EXPECT_SHA="c8ff1c45b053680261074e5faa41c7d25b653004154c7b86af4c6775e5af3eb7"

echo "==> 1/4 安装 tftpd-hpa 与 tcpdump"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq tftpd-hpa tcpdump curl

echo "==> 2/4 配置 tftpd-hpa (/srv/tftp)"
mkdir -p /srv/tftp
chmod 755 /srv/tftp
cat > /etc/default/tftpd-hpa <<'EOF'
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure --create"
EOF
systemctl restart tftpd-hpa
systemctl is-active tftpd-hpa || { echo "tftpd-hpa 启动失败"; exit 1; }

echo "==> 3/4 复制固件到 /srv/tftp"
if [ $# -ge 1 ]; then
	for f in "$@"; do
		[ -f "$f" ] || { echo "文件不存在: $f"; exit 1; }
		cp -f "$f" /srv/tftp/
	done
	chown root:root /srv/tftp/*.itb 2>/dev/null || true
	chmod 644 /srv/tftp/*.itb 2>/dev/null || true
else
	echo "    (未提供固件文件;下一步用 pi-fetch-firmware.sh 直接从 GitHub Releases 下载)"
fi

echo "==> 4/4 校验 /srv/tftp 内容"
ls -la /srv/tftp/
if ls /srv/tftp/*sysupgrade*.itb >/dev/null 2>&1; then
	echo
	echo "--- 固件 sha256 (sysupgrade 必须等于 $EXPECT_SHA) ---"
	sha256sum /srv/tftp/*sysupgrade*.itb
fi

echo
echo "-------------------------------------------------------------"
echo "下一步(推荐):直接在树莓派上下载官方发布的固件"
echo "  sudo sh pi-fetch-firmware.sh --install"
echo
echo "下载后 u-boot 会来请求这个确切文件名:"
echo "  immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb"
echo "确认时抓包看 RRQ (另开一个 SSH 会话,走 WiFi):"
echo "  sudo tcpdump -i eth0 -n -e udp port 69"
echo "-------------------------------------------------------------"
