# 刷机工具包(树莓派 TFTP 整刷)

这套脚本把前三轮实战中踩过的坑**固化成了命令**,配合 u-boot 的 TFTP 恢复模式整机刷写固件。

> 适用:Netcore N30 Pro(Netis NX30V2 / POWER30AX / GW3001 / GLC W7 同硬件),
> 已刷入 ImmortalWrt 官方 u-boot(`immortalwrt-…-netis_nx30v2-spim-nand-bl31-uboot.fip`)。
> 该 u-boot 的默认环境里:
> `boot_nand=ubi read $loadaddr fit; bootm $loadaddr#config-1`
> `bootfile_fw=immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb`
> `upgrade_fw=… tftpboot $bootfile_fw && … ubi remove fit; ubi create fit; ubi write …`
> 即:**TFTP 整刷会直接重建 `fit` 卷**,绕开系统内 sysupgrade 的一切脚本问题,是最可靠的路径。

---

## 拓扑

```
MacBook ──WiFi/SSH──> 树莓派 ──网线(eth0)──> 路由器(进 u-boot 恢复模式)
                       (TFTP 服务器 192.168.1.254)     (u-boot IP 192.168.1.1)
```

关键点:**Mac 通过 WiFi 连树莓派**(不要用 eth0 那条链路做 SSH),eth0 专门做 TFTP 点对点。

---

## 步骤

### 0. 把脚本弄到树莓派上(二选一)

**情况 A(推荐,树莓派能上外网)**:树莓派自己从公开仓库拉脚本,连 Mac 都不用

```sh
# 在树莓派上执行(SSH 进去之后)
mkdir -p ~/n30kit && cd ~/n30kit
for f in pi-setup-tftp.sh pi-fetch-firmware.sh pi-net-on.sh pi-net-off.sh verify-after-boot.sh; do
    curl -fsSLO https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/flash-kit/$f
done
ls -la
```

**情况 B(树莓派不能上外网)**:在 Mac 上下载仓库(zip 或 clone)后 scp 过去

```sh
PI=mypi@raspberrypi.local        # 改成你的树莓派地址(WiFi 那个)
scp -O flash-kit/*.sh $PI:/tmp/
```

### 1. 树莓派:装 TFTP 服务

```sh
ssh $PI
sudo sh ~/n30kit/pi-setup-tftp.sh          # 情况 B 则用 /tmp/pi-setup-tftp.sh
```

装了 `tftpd-hpa` + `tcpdump`(`curl`),建好 `/srv/tftp`。

### 2. 树莓派:直接下载官方固件并校验就位(无需 Mac 中转)

```sh
sudo sh ~/n30kit/pi-fetch-firmware.sh --install
```

做了四件事:自动取**最新 Release**(取不到回落 `v1.0.0`)→ 下载 `SHA256SUMS` 与两个 `.itb`
→ **自动校验 sha256** → 复制进 `/srv/tftp` 并重启服务。

可选参数:

```sh
--with-uboot          # 顺便下载"从原厂系统开始"要用的官方 u-boot FIP
--version v1.0.0      # 指定版本
--base-url https://<镜像前缀>/https://github.com   # 走镜像(国内网络慢时)
--dest /tmp/xxx       # 指定下载目录
```

> Mac 中转的备用做法(仅当树莓派完全没网时):Mac 上从仓库 Releases 下载两个 `.itb`,
> 再 `scp -O *.itb $PI:/tmp/` 然后 `sudo sh ~/n30kit/pi-setup-tftp.sh /tmp/*.itb`。

### 3. 树莓派:打开救砖链路(三个大坑都在这里)

```sh
sudo sh ~/n30kit/pi-net-on.sh
```

它做了四件事(全部来自实战踩坑):

| 坑 | 脚本里的处理 |
|---|---|
| `ip route add` 被 NetworkManager 定时刷掉 | 把 `192.168.1.1/32` 主机路由**写进 nmcli 连接**(`ipv4.routes "192.168.1.1/32 0.0.0.0 50"`) |
| 同网段有 wlan0 路由,光靠 metric 仍走 wlan0 | `ip route replace 192.168.1.1/32 dev eth0 **src 192.168.1.254** metric 50` |
| `rp_filter=2` 也会丢 TFTP 回包 | `rp_filter=0`(eth0/all/default)并写入 `/etc/sysctl.d/99-tftp-recovery.conf` |

**PASS 标准**(脚本会打印):`ip route get 192.168.1.1` → `dev eth0 src 192.168.1.254`;
`cat /proc/sys/net/ipv4/conf/eth0/rp_filter` → `0`;`tftpd-hpa` → active。
等 30~60 秒再确认一次路由还在。

### 4. 抓包窗口(另开一个 SSH,不要复用旧窗口)

```sh
sudo tcpdump -i eth0 -n -e udp port 69
```

### 5. 路由器进 u-boot 并整刷

1. 拔掉路由器 WAN 口那根上网线(避免 192.168.1.1 与家里网关撞车);
2. 断电 → 按住 Reset → 上电 → 保持约 10 秒 → 松开;
3. 观察 tcpdump:

| 看到什么 | 含义 |
|---|---|
| `RRQ "immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb"` + 连续 ~1472 字节 DATA | 正常,正在刷 |
| `RRQ "…initramfs.itb"` | u-boot 走的是"启动内存系统"分支,说明你选到了 recovery 项 |
| 19 字节的 UDP 回包 | TFTP 报"文件不存在" → 文件名与 RRQ 不一致,改名 |
| 什么都抓不到 | 检查网线/端口(换一个 LAN 口试)、eth0 链路、路由与 rp_filter |

4. 传输完成(最后一个 DATA 包 < 1472 字节)后,u-boot 会 `ubi remove fit; ubi create fit; ubi write`,
   期间**绝对不要断电**,等它自己重启。

### 6. 刷完自检

```sh
# Mac 上:
ssh root@192.168.1.1 'sh -s' < ~/n30kit/verify-after-boot.sh
# 或先把脚本拷到路由器再跑
```

PASS 标准:`DISTRIB_REVISION=r37877-n30pro`;9 个代理 kmod 全部 OK;`dmesg` 无 `supply vbus not found`;
`/sys/firmware/devicetree/base/regulator-usb-vbus` 存在。

### 7. 收尾

```sh
sudo sh ~/n30kit/pi-net-off.sh          # 删掉恢复路由/连接,rp_filter 复原
# 或保留连接只改回 DHCP:
sudo sh ~/n30kit/pi-net-off.sh --restore-dhcp
```

---

## 常见问题

* **system 内 `sysupgrade` 提示成功但版本没变** → 见 `docs/04-第二轮-根因修复说明(sysupgrade写错卷).md`;
  用本工具包的 TFTP 整刷一定生效。
* **19 字节回包** → 文件名不是 u-boot 要的那个,按 tcpdump 抓到的 RRQ 改名。
* **只想临时试固件、不写 flash** → 让 u-boot 走 `boot_recovery`(请求 `…initramfs.itb`),它只把系统拉进内存。
* **树莓派把自己锁在外面** → 别在 eth0 这条链路上做 SSH;关 WiFi 前先确认有别的通道。
