#!/bin/sh
# ============================================================
# 在【树莓派】上运行：准备 TFTP 服务器(不改网络配置)
#   用法:  sh pi-setup-tftp.sh /path/to/n30pro-*.itb [...]
#   作用:  安装 tftpd-hpa、建 /srv/tftp、把固件放进去并校验 sha256
#   注意:  这一步请在树莓派【还能上网】时做(apt 需要网络)
# ============================================================
set -e

if [ "$(id -u)" != "0" ]; then
	echo "请用 sudo 运行: sudo sh $0 <固件文件...>"
	exit 1
fi

[ $# -ge 1 ] || { echo "用法: sudo sh $0 <固件文件...>"; exit 1; }

EXPECT_SHA="c8ff1c45b053680261074e5faa41c7d25b653004154c7b86af4c6775e5af3eb7"

echo "==> 1/4 安装 tftpd-hpa 与 tcpdump"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq tftpd-hpa tcpdump

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
for f in "$@"; do
	[ -f "$f" ] || { echo "文件不存在: $f"; exit 1; }
	cp -f "$f" /srv/tftp/
done
chown root:root /srv/tftp/*.itb 2>/dev/null || true
chmod 644 /srv/tftp/*.itb 2>/dev/null || true

echo "==> 4/4 校验 /srv/tftp 内容"
ls -la /srv/tftp/
echo
echo "--- 固件 sha256 (sysupgrade 必须等于 $EXPECT_SHA) ---"
sha256sum /srv/tftp/*sysupgrade*.itb

echo
echo "-------------------------------------------------------------"
echo "接下来u-boot 会来请求这个确切文件名:"
echo "  immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb"
echo "如需确认,抓包看 RRQ (另开一个 SSH 会话,走 WiFi):"
echo "  sudo tcpdump -i eth0 -n -e udp port 69"
echo "-------------------------------------------------------------"
