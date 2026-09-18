#!/bin/sh
# ============================================================
# 刷完固件后,在【路由器】上运行(或 ssh root@192.168.1.1 'sh -s' < 本脚本)
# 作用:一次性确认"新固件确实生效 + USB/代理模块都在"
# ============================================================
echo "================ 刷机结果自检 ================"
echo "--- 1. 固件指纹(应为 r37877-n30pro) ---"
grep -E "DISTRIB_REVISION|DISTRIB_DESCRIPTION" /etc/openwrt_release 2>/dev/null
echo "构建标识: $(cat /etc/usb-fix-id 2>/dev/null)"

echo
echo "--- 2. 内核版本(本轮为 6.12.91,ABI 哈希应含 122562b1) ---"
uname -r
(apk info kernel 2>/dev/null || opkg list-installed 2>/dev/null | grep -E '^kernel ') | head -2

echo
echo "--- 3. openclash / passwall 所需内核模块 ---"
[ -x /usr/bin/apk ] && PKGS="$(apk info 2>/dev/null)" || PKGS="$(opkg list-installed 2>/dev/null | cut -d' ' -f1)"
for k in kmod-tun kmod-nft-tproxy kmod-nft-socket kmod-inet-diag kmod-netlink-diag \
         kmod-nft-nat kmod-nft-fib kmod-nf-reject kmod-nf-reject6; do
	printf "  %-22s %s\n" "$k" "$(echo "$PKGS" | grep -qx "$k" && echo OK || echo "缺失!")"
done

echo
echo "--- 4. 对应 .ko 文件 ---"
ls /lib/modules/*/ 2>/dev/null | grep -E "^(tun|nft_tproxy|nft_socket|nft_nat|inet_diag|netlink_diag)\.ko" | sort

echo
echo "--- 5. USB VBUS 供电(应无 'supply vbus not found') ---"
dmesg 2>/dev/null | grep -i "supply vbus" || echo "OK: 已无 dummy regulator 告警"

echo
echo "--- 6. 设备树里的供电节点 ---"
DT=/sys/firmware/devicetree/base
[ -d "$DT/regulator-usb-vbus" ] && echo "OK: regulator-usb-vbus 存在" || echo "缺失 regulator-usb-vbus!"
[ -e "$DT/soc/usb@11200000/vbus-supply" ] && echo "OK: xhci 含 vbus-supply" || echo "缺失 vbus-supply!"

echo
echo "--- 7. 当前 USB 设备与网卡(F50 插上后应多出设备/接口) ---"
ls /sys/bus/usb/devices/ 2>/dev/null
ip -br link 2>/dev/null

echo
echo "--- 8. 已安装的相关应用 ---"
echo "$PKGS" | grep -E "^(luci-app-openclash|luci-app-passwall|sing-box|xray-core)" || echo "(尚未安装 openclash/passwall,可按需 apk add)"
echo "================ 自检结束 ================"
