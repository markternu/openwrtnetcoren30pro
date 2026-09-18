#!/bin/sh
# ============================================================
# 树莓派:打开 TFTP 救砖链路(按第二轮实战结论固化)
#   1) eth0 静态 192.168.1.254/24(不设网关)
#   2) 持久化主机路由 192.168.1.1/32 -> eth0 (写进 nmcli,防被刷新)
#   3) 显式 src 192.168.1.254,消除与 wlan0 的抢路
#   4) rp_filter eth0 = 0(第二轮的关键坎:2 也会丢 TFTP 回包)
# 用法: sudo sh pi-net-on.sh
# ============================================================
set -e
[ "$(id -u)" = "0" ] || { echo "请用 sudo 运行"; exit 1; }

IFACE=eth0
CON=recovery
IP=192.168.1.254
GW=192.168.1.1          # 救砖期间路由器的地址,也是家里网关的常见地址

echo "==> 0/5 当前网卡状态"
ip -br addr show $IFACE || true
command -v nmcli >/dev/null 2>&1 || { echo "此脚本依赖 NetworkManager(nmcli);若系统用 dhcpcd 请手工配置 $IFACE"; exit 1; }

echo "==> 1/5 写入 nmcli 连接(静态 IP + 持久主机路由)"
nmcli con show "$CON" >/dev/null 2>&1 || nmcli con add type ethernet ifname $IFACE con-name "$CON"
nmcli con modify "$CON" \
	ipv4.method manual \
	ipv4.addresses ${IP}/24 \
	ipv4.gateway "" \
	ipv4.never-default yes \
	ipv4.routes "${GW}/32 0.0.0.0 50" \
	ipv6.method disabled
nmcli con down "$CON" >/dev/null 2>&1 || true
nmcli con up "$CON"

echo "==> 2/5 消除同网段歧义:删掉 eth0 上会抢路的 /24 路由(如有)"
ip route del 192.168.1.0/24 dev $IFACE 2>/dev/null || true

echo "==> 3/5 强制绑定:主机路由 + 显式源地址"
ip route replace ${GW}/32 dev $IFACE src $IP metric 50

echo "==> 4/5 关闭 rp_filter(反向路径过滤)并固化"
cat > /etc/sysctl.d/99-tftp-recovery.conf <<EOF
net.ipv4.conf.${IFACE}.rp_filter=0
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF
/sbin/sysctl -w net.ipv4.conf.${IFACE}.rp_filter=0 >/dev/null
/sbin/sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
/sbin/sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null
systemctl restart systemd-sysctl 2>/dev/null || true

echo "==> 5/5 自检"
echo "--- 地址 ---";            ip -br addr show $IFACE
echo "--- 路由表 ---";          ip route show | grep -E "192\.168\.1\.(1|0)" || true
echo "--- 去 192.168.1.1 走哪 ---"; ip route get $GW
echo "--- rp_filter(eth0 必须为 0) ---"; cat /proc/sys/net/ipv4/conf/${IFACE}/rp_filter
echo "--- TFTP 服务 ---"; systemctl is-active tftpd-hpa 2>/dev/null || echo "(tftpd-hpa 未安装/未运行)"
echo "--- 文件 ---"; ls -la /srv/tftp/ 2>/dev/null | tail -n +2

echo
echo "==================== PASS 标准 ===================="
echo "1) ip route get $GW 输出里:dev $IFACE src $IP"
echo "2) cat /proc/sys/net/ipv4/conf/$IFACE/rp_filter  -> 0"
echo "3) systemctl is-active tftpd-hpa -> active"
echo "4) /srv/tftp 内有固件且 sha256 正确"
echo "建议等 30~60 秒再跑一次 'ip route get $GW' 确认没被 NetworkManager 刷掉。"
echo "==================================================="
