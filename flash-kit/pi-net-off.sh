#!/bin/sh
# ============================================================
# 树莓派:救砖完成后清理(恢复日常网络)
# 用法: sudo sh pi-net-off.sh [--restore-dhcp]
# ============================================================
set -e
[ "$(id -u)" = "0" ] || { echo "请用 sudo 运行"; exit 1; }

IFACE=eth0
CON=recovery
RESTORE_DHCP=no
[ "$1" = "--restore-dhcp" ] && RESTORE_DHCP=yes

echo "==> 1/4 移除临时主机路由与 rp_filter 固化"
ip route del 192.168.1.1/32 dev $IFACE 2>/dev/null || true
rm -f /etc/sysctl.d/99-tftp-recovery.conf
/sbin/sysctl -w net.ipv4.conf.${IFACE}.rp_filter=2 >/dev/null 2>&1 || true
systemctl restart systemd-sysctl 2>/dev/null || true

echo "==> 2/4 处理 nmcli 连接"
if [ "$RESTORE_DHCP" = "yes" ]; then
	nmcli con modify "$CON" ipv4.method auto ipv4.addresses "" ipv4.routes "" ipv4.never-default no 2>/dev/null || true
	echo "   已把 $CON 改回 DHCP(保留连接)"
else
	nmcli con down "$CON" 2>/dev/null || true
	nmcli con delete "$CON" 2>/dev/null || true
	echo "   已删除连接 $CON"
fi

echo "==> 3/4 恢复无线(如之前用 nmcli radio wifi off 关过)"
nmcli radio wifi on 2>/dev/null || true

echo "==> 4/4 结果"
ip -br addr show $IFACE 2>/dev/null || true
nmcli -t -f NAME,DEVICE,TYPE con show --active 2>/dev/null | head -5
echo "清理完成。"
