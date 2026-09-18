# 第三轮刷机全过程教程(环境确认 → 传物料 → 树莓派自检 → Reset 进 u-boot → 验证)

> ✅ **本教程已按 2026-09-10 的实刷结果修订**:真正的成功触发是「断电后**等 20 秒放电** + 按住 Reset **20 秒**」——
> 按 10 秒连续两次都没进恢复模式;改成 20 秒后**一次成功**,10000 个满包 + 358 尾包、一个字节不差。
> 详见文末 **附录 D:本轮实刷补遗**。

> 本教程把《第三轮交付说明-补齐代理内核模块.md》《刷机教程.md》与《历史对话.md》里**第二轮实刷踩过的所有坑**
> 合并成一条可直接照做的流水线。核心结论先说:
>
> **第二轮的失败不是"文件不对",而是树莓派侧的网络环境(路由选择 + rp_filter)让 TFTP 回包发不出去。**
> 所以本次的重点不在刷机动作本身,而在**第 3 节(树莓派自检)必须全部 PASS 之后再去按 Reset**。

---

## 0. 本轮为什么要整机重刷(不能只装 kmod)

| | 第二轮(现在设备里跑的) | 第三轮(本次要刷的) |
|---|---|---|
| 固件 sha256 | `d63676453383e92fb454b1ca3e375959dc8a2b8b144ea22a37c6be28d8b50340` | `c8ff1c45b053680261074e5faa41c7d25b653004154c7b86af4c6775e5af3eb7` |
| 内核 ABI(`grep ^kernel *.manifest`) | `6.12.91~9981310e33c111e5eb06587b6ecadcfa` | `6.12.91~122562b1ee0c22b0eb77d2808e0bd84f` |
| 内核模块 | 无 tun / nft-tproxy 等 | 已内置 `kmod-tun`、`kmod-nft-tproxy`、`kmod-nft-socket`、`kmod-inet-diag`、`kmod-netlink-diag`、`kmod-nft-nat`、`kmod-nft-fib`、`kmod-nf-reject(6)` |

内核配置变了 → 内核包哈希变了 → 新 kmod 的 `.apk` **装不进第二轮固件**(会报 ABI / `breaks:` 不匹配),
所以**必须整机刷入**。刷机方式与第二轮相同,推荐 **u-boot TFTP 整刷**。

> ⚠️ 交付说明里有一处笔误:`6.12.91~122562b1ee0c22b0eb77d2808e0bd84f` 被写成了"上一轮镜像"的哈希,
> 实际它是**本轮新哈希**;上一轮(现网)是 `9981310e33c111e5eb06587b6ecadcfa`。
> 以自己 `grep ^kernel *.manifest` 的结果为准,别被文档里的括号说明绕晕。

### 刷机前必做:把第二轮系统的配置备份出来

u-boot TFTP 整刷是**全新写入**,配置会清空(第二轮刷完就是"no root password defined")。
所以先把现在能进的系统里的配置导出来:

```bash
# Mac 上先清掉旧 host key(第二轮刷完 host key 变了,不清会报 REMOTE HOST IDENTIFICATION HAS CHANGED)
ssh-keygen -R 192.168.1.1

ssh root@192.168.1.1
# 路由器上:
sysupgrade -b /tmp/backup-$(date +%F).tar.gz
exit
# Mac 上拉回来:
scp -O root@192.168.1.1:/tmp/backup-*.tar.gz ~/Desktop/luyouqi/
```

> 本机 Mac 的 `~/.ssh/known_hosts` 里**已经存在** 192.168.1.1 的冲突条目(已确认),上面第一条命令是必须的。

---

## 1. 阶段一:Mac 上校验物料(约 3 分钟)

```bash
cd /Users/wt/Desktop/luyouqi/deliverables/firmware
shasum -a 256 *.itb *.manifest
```

期望值(**本机已实测核对过,全部一致**):

| 文件 | 字节数 | 期望 sha256 |
|---|---|---|
| `immortalwrt-mediatek-filogic-netcore_n30pro-squashfs-sysupgrade.itb` | 14,680,358 | `c8ff1c45b053680261074e5faa41c7d25b653004154c7b86af4c6775e5af3eb7` |
| `immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb` | 14,680,358 | `c8ff1c45b053680261074e5faa41c7d25b653004154c7b86af4c6775e5af3eb7`(与上面同一个文件,只是改了名给 u-boot 用) |
| `immortalwrt-mediatek-filogic-netcore_n30pro-initramfs.itb` | 12,386,304 | `28dd45d9bf76121f968ed958c55bcd492e84fc31551e39d3ad12951007190acd` |
| `immortalwrt-mediatek-filogic-netis_nx30v2-initramfs.itb` | 12,386,304 | 同上(同一文件) |
| `immortalwrt-mediatek-filogic-netcore_n30pro.manifest` | 6,535 | `2be58bcb1725d60f04b05c958a98c712d54c26fc16b0379044427534fe55b936` |

### 🚨 头号陷阱:第三轮和第二轮**字节数完全一样**

第二轮的 sysupgrade 和第三轮的 sysupgrade **都是 14,680,358 字节**,只有哈希不同。
树莓派 `/srv/tftp` 里那个第二轮旧文件**同名、同大小**——所以:

> **在树莓派上靠 `ls -la` 看大小/日期判断"传的是新固件"一定会判断错,必须比对 sha256。**

顺手核对第三轮特征(确认拿到的是补齐 kmod 的那一版):

```bash
grep -E "^kernel " /Users/wt/Desktop/luyouqi/deliverables/firmware/*.manifest
# 必须是 6.12.91~122562b1ee0c22b0eb77d2808e0bd84f-r1

grep -E "kmod-(tun|nft-tproxy|nft-socket|inet-diag|netlink-diag|nft-nat|nft-fib|nf-reject)" \
     /Users/wt/Desktop/luyouqi/deliverables/firmware/*.manifest
# 应列出: kmod-inet-diag / kmod-netlink-diag / kmod-nf-reject / kmod-nf-reject6 /
#         kmod-nf-socket / kmod-nf-tproxy / kmod-nft-core / kmod-nft-fib /
#         kmod-nft-nat / kmod-nft-socket / kmod-nft-tproxy / kmod-tun
```

### 确认树莓派和路由器都在线、Mac 能摸到它们

```bash
ping -c 2 192.168.1.165     # 树莓派
ping -c 2 192.168.1.1       # 路由器(现在跑的是第二轮固件)
ipconfig getifaddr en0      # Mac 自己的地址(当前为 192.168.1.201)
```

> 说明:树莓派 `192.168.1.165` 是**走 WiFi** 的地址。救砖链路必须走**网线 eth0(192.168.1.254)**,
> 这一点是第二轮所有诡异现象的根源,见第 3 节。

---

## 2. 阶段二:把物料传到树莓派

### 方式 A:手动两步(和之前一样,推荐,可控)

```bash
# ① Mac → 树莓派 /tmp
scp -O /Users/wt/Desktop/luyouqi/deliverables/firmware/immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb \
       mypi@192.168.1.165:/tmp/

# ② 树莓派 → TFTP 目录
ssh mypi@192.168.1.165
sudo cp /tmp/immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb /srv/tftp/
sudo chown root:root /srv/tftp/*.itb && sudo chmod 644 /srv/tftp/*.itb
```

### 方式 B:用交付的脚本一键准备(会顺带装好 tftpd-hpa / tcpdump)

```bash
scp -O /Users/wt/Desktop/luyouqi/deliverables/firmware/*.itb mypi@192.168.1.165:/tmp/
scp -O /Users/wt/Desktop/luyouqi/deliverables/tftp-flash-kit/pi-setup-tftp.sh mypi@192.168.1.165:/tmp/
ssh mypi@192.168.1.165
sudo sh /tmp/pi-setup-tftp.sh /tmp/immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb
# 注意:脚本里 apt-get 需要树莓派【能上网】,这一步请在还没断开日常网络前做
```

### 传完**必须**验证哈希(这一步不能省)

```bash
sha256sum /srv/tftp/immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb
```

**输出必须等于** `c8ff1c45b053680261074e5faa41c7d25b653004154c7b86af4c6775e5af3eb7`。

- 如果看到 `d6367645…` → 那是**第二轮的旧文件**,`cp` 没覆盖成功,重做第 2 步。
- 顺便看一眼目录:`ls -la /srv/tftp`。里面那个 5 月的旧 `…-initramfs.itb` 不影响本轮(u-boot 请求的是 sysupgrade 文件名),
  但**如果你的 sysupgrade 文件日期没变成今天,就是没覆盖**,务必回头查。

---

## 3. 阶段三:树莓派环境自检(本轮真正的关键,6 项必须全 PASS)

> 第二轮就是在这一步没查干净:文件、服务、自测**全部正常**,但 u-boot 的 RRQ 一个回包都收不到。
> 根因有两个,必须**同时**解决:
> **(1) 内核去 192.168.1.1 走的是 wlan0 而不是 eth0;(2) rp_filter 丢包。**
>
> 也可以直接跑交付的一键脚本(见文末附录 C):
> `scp -O pi-preflight-check.sh mypi@192.168.1.165:/tmp/ && ssh mypi@192.168.1.165 'sudo sh /tmp/pi-preflight-check.sh'`

### ① TFTP 服务在跑、在监听 69

```bash
sudo systemctl status tftpd-hpa --no-pager
sudo ss -ulnp | grep 69
```

PASS 标准:

```
Active: active (running) …
UNCONN 0 0 0.0.0.0:69 0.0.0.0:* users:(("in.tftpd",…))
```

不在跑就重启:`sudo systemctl restart tftpd-hpa`

### ② 文件在、哈希对

```bash
ls -la /srv/tftp
sha256sum /srv/tftp/*sysupgrade*.itb      # = c8ff1c45…
```

### ③ 网线物理链路 + 静态 IP

```bash
ip addr show eth0
cat /sys/class/net/eth0/carrier
```

PASS 标准:网线接在**路由器的 LAN 口**;`state UP` 且 `<…,LOWER_UP>`;`carrier` = `1`;
inet 有 `192.168.1.254/24`。

- `carrier` = `0` / `NO-CARRIER` → 网线没插好或插的是路由器 WAN 口,先解决物理链路。
- 没有 `192.168.1.254/24` → 建连接(见下一条)。

```bash
sudo nmcli con add type ethernet ifname eth0 con-name recovery ip4 192.168.1.254/24
sudo nmcli con up recovery
```

### ④ 路由(第二大坑:临时路由会被冲掉,metric 还不够)

**先记住两个结论,来自第二轮的实战:**

1. `sudo ip route add 192.168.1.1/32 dev eth0 metric 50` 这种**临时**命令会被 **NetworkManager 定时刷新冲掉**
   (第二轮亲眼看到:加了之后过一会儿自己消失了)。→ 必须写进 nmcli 连接配置。
2. 只有 `metric 50` **不够**:第二轮 `ip route get 192.168.1.1` 依然显示走 `wlan0`(因为同网段还活着一条 wlan0 路由)。
   → 必须**显式指定源地址 `src 192.168.1.254`**,内核才会真正锁定 eth0。

**正确做法(一条命令,注意 `&&` 串联):**

```bash
sudo nmcli con modify recovery +ipv4.routes "192.168.1.1/32 0.0.0.0 50" && sudo nmcli con down recovery && sudo nmcli con up recovery && ip route show && ip route get 192.168.1.1
```

**PASS 标准(这两行必须同时成立):**

```
192.168.1.1 dev eth0 proto static scope link metric 50        ← 路由在,且是 proto static(持久的)
192.168.1.1 dev eth0 src 192.168.1.254 uid 1000               ← 真的走 eth0,源地址是 254
```

如果 `ip route get` 还是显示 `dev wlan0 src 192.168.1.165`,按顺序试:

```bash
# a) 先删掉 eth0 上那条会抢路的 /24 网段路由(消除歧义)
sudo ip route del 192.168.1.0/24 dev eth0

# b) 还不行就强制指定 src(第二轮就是这么救回来的)
sudo ip route replace 192.168.1.1/32 dev eth0 src 192.168.1.254 metric 50

# c) 确认
ip route get 192.168.1.1
```

**稳定性复检(重要)**:等 `30~60` 秒,什么都不改,再跑一次:

```bash
ip route get 192.168.1.1
```

仍然是 `dev eth0 src 192.168.1.254` 才算稳定。如果又变回 wlan0,说明路由又被刷新了——
那就回到 (b) 用 `nmcli` 把 `src` 也写进配置,或者干脆**在救砖期间临时关掉 wlan0**:

```bash
sudo nmcli radio wifi off          # 救完砖再 nmcli radio wifi on 打开
# 注意:关掉 WiFi 后你就不能用 192.168.1.165 这个地址 SSH 了!
# → 必须先确认能通过 eth0 直连路由器(或直接用键盘/显示器)再关,否则会把自己锁在外面
```

> 顺带说明:第二轮一开始之所以会"只请求、没回应",就是这个 wlan0/eth0 抢路问题;
> 而**救砖期间路由器自己的 IP 正好也是 192.168.1.1,和家里网络的网关撞车**,所以这个问题尤其容易触发。
> 有条件的做法是:救砖时把路由器 WAN 口那根上网网线**拔掉**,让 eth0 这条链路纯粹点对点。

### ⑤ rp_filter(第三大坑,第二轮的最后一道坎)

```bash
sudo /sbin/sysctl net.ipv4.conf.eth0.rp_filter net.ipv4.conf.wlan0.rp_filter net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter
```

> ⚠️ 注意:`sysctl` 不在这台树莓派的 PATH 里,直接敲 `sysctl` 会 `command not found`。
> 用 `/sbin/sysctl`,或者直接读文件:`cat /proc/sys/net/ipv4/conf/eth0/rp_filter`

**PASS 标准:`eth0` 必须是 `0`。**

第二轮实测是 `2`(宽松模式)——**而 `2` 依然把 TFTP 回包丢了**。改成 0 之后,同一个文件、
同一个服务、同一套路由,传输**立刻成功**(抓到连续的 1472 字节 DATA 包)。

```bash
sudo sysctl -w net.ipv4.conf.eth0.rp_filter=0
sudo sysctl -w net.ipv4.conf.default.rp_filter=0
cat /proc/sys/net/ipv4/conf/eth0/rp_filter      # 必须输出 0
```

固化一下(免得后面被别的动作带回去):

```bash
echo -e 'net.ipv4.conf.eth0.rp_filter=0\nnet.ipv4.conf.default.rp_filter=0\nnet.ipv4.conf.all.rp_filter=0' | sudo tee /etc/sysctl.d/99-tftp-recovery.conf
sudo systemctl restart systemd-sysctl 2>/dev/null || true
```

### ⑥ 树莓派本机自测(排除服务/权限问题)

```bash
tftp 192.168.1.254 -c get immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb /tmp/selftest.itb
ls -la /tmp/selftest.itb
```

PASS 标准:拿到 **14,680,358 字节**。

> 注意区分:第二轮时**本机自测是成功的**,但路由器请求没回应 → 说明问题一定在"网络路径"上,
> 而不是 tftpd 服务。所以本机自测通过**不能**作为"环境 OK"的结论,必须结合 ④⑤ 一起看。

可选:确认没有防火墙在挡

```bash
sudo nft list ruleset 2>&1 | head -30     # 若 command not found 说明没装 nftables,可忽略
sudo iptables -S 2>&1 | head -20
```

### 自检结论表(全部 YES 才去按 Reset)

| # | 检查项 | 通过标准 |
|---|---|---|
| 1 | tftpd-hpa | active + 监听 0.0.0.0:69 |
| 2 | /srv/tftp 文件 | sha256 = `c8ff1c45…` |
| 3 | eth0 链路/IP | carrier=1、UP、192.168.1.254/24 |
| 4 | 路由 | `ip route get 192.168.1.1` → `dev eth0 src 192.168.1.254`,且 60 秒后仍如此 |
| 5 | rp_filter | eth0 = 0 |
| 6 | 本机自测 | 拉到完整 14,680,358 字节 |

---

## 4. 阶段四:Reset 进 u-boot + 抓包判读

### 先开抓包窗口(另开一个 SSH 会话,不要复用旧窗口)

```bash
ssh mypi@192.168.1.165
sudo tcpdump -i eth0 -n udp port 69
```

> 🚨 **坑**:第二轮曾经把一个**旧的 tcpdump 窗口**当成新结果看,里面全是修复路由**之前**的失败记录,
> 白白多绕一轮。**每次改完配置/重新触发,都按 Ctrl+C 关掉、重开一个全新窗口。**

### 手动触发救砖模式

> ⚠️ **时长是本轮实刷出来的关键**:按 10 秒试了两次都没进恢复模式(路由器直接正常开机跑旧系统);
> 改成「拔电后**等 20 秒放电** + 按住 Reset **20 秒**」**一次就进**。宁长勿短。

1. 拔掉电源,**等 20 秒**(让电容放电——这一步不能省);
2. **按住 Reset 键不放**;
3. 保持按住的同时,**插上电源**;
4. 继续按住 Reset,**数到 20**;
5. 松开 Reset;
6. **松开后再等 60 秒**再看抓包结果(别急着判定失败)。

**想确认服务端到底有没有收到请求,再配一个链路监视**(读 `/sys` 不需要 sudo):

```bash
nohup sh -c 'while true; do echo "$(date +%T) carrier=$(cat /sys/class/net/eth0/carrier)"; sleep 1; done' > /tmp/carrier.log 2>&1 &
```

`carrier` 的 `1→0`(断电)`0→1`(上电)两次跳变,正好把"你什么时候动的电源"钉在时间轴上,
是区分"没进恢复模式"和"回包被丢"的最快证据。

### tcpdump 判读表(对号入座)

| 看到什么 | 含义 | 怎么办 |
|---|---|---|
| `RRQ "…itb"` 后紧跟 `UDP, length 19` | **文件不存在**(19 字节 = 错误包) | 文件名/路径不对,按抓到的名字改名;确认 `/srv/tftp` 权限 644 |
| 只有 `RRQ` 反复出现,**零回包** | 树莓派收到了但回不出去 | 回到第 3 节 ④路由 / ⑤rp_filter,改完**重开 tcpdump + 重新 Reset** |
| 连续 `UDP, length 1472` + 4 字节确认包 | ✅ 正在传输 | 等它跑完 |
| 最后出现 **小于 1472** 的 DATA(如 `length 362`) | ✅ **传输完成**,固件已交给 u-boot | 随后会出现 `ARP, Request who-has 192.168.1.1 tell 192.168.1.254` = 开始写 flash 并重启 |

> RRQ 里请求的文件名**应该是**:`immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb`
> (这是原厂 netis_nx30v2 u-boot 的 `bootfile_fw`;交付件已经按这个名字预改名好了)

### 如果一直没动静

u-boot 的 TFTP 恢复**不会无限重试**——失败若干次后会**放弃并正常启动 flash 里的旧系统**(第二轮实测就是这样)。
所以如果 10 秒以上完全没新包:

```bash
ping 192.168.1.1 && ssh root@192.168.1.1 'grep DISTRIB_REVISION /etc/openwrt_release'
```

- 能进去、版本是 `r37877-n30pro`(第二轮) → 证实它已放弃 TFTP,回了旧系统。
  **用完整流程重新触发一遍**(断电 → 等 20 秒 → 按住 Reset → 插电 → 数到 20 → 松开),这次路由/rp_filter 已经修好,应当能一次过。
- 进不去也 ping 不通 → 说明它还在等待或状态异常,再等 30 秒重新抓包;仍无则重新触发。

> 别指望"它还在上一轮的重试循环里等着"——重启一次抓包窗口要比重试更可靠。

---

## 5. 阶段五:刷完验证(第三轮专属)

等 1~2 分钟:

```bash
ping 192.168.1.1
ssh-keygen -R 192.168.1.1        # 换了固件=host key 变了,一定会报,先清掉(第二轮/本机都遇到过)
ssh root@192.168.1.1
```

**全新系统没有 root 密码**,进去先设:`passwd`

### ① 固件指纹(最直接的"这次真的换了"证据)

```bash
grep DISTRIB_REVISION /etc/openwrt_release
```

必须 = `r37877-n30pro`。

> 说明:第二轮的版本号**也是** `r37877-n30pro`(它相对的是更早的 `r37877-3c71dfc2b6`),
> 所以**版本号本身不足以区分第二/第三轮**。第三轮要用下面的内核 ABI 与 kmod 清单来区分。

```bash
uname -r                 # 6.12.91
apk info | grep '^kernel' # 必须含 6.12.91~122562b1ee0c22b0eb77d2808e0bd84f
```

### ② 第三轮的核心断言:代理内核模块都在

```bash
apk info | grep -E "kmod-(tun|nft-tproxy|nft-socket|inet-diag|netlink-diag|nft-nat|nft-fib|nf-reject)"

# 等价的内核模块文件断言(更硬)
ls /lib/modules/$(uname -r)/ | grep -E "^(tun|nft_tproxy|nft_socket|nft_nat|nft_fib|nf_reject_ipv4|nf_reject_ipv6|inet_diag|netlink_diag)\.ko"
```

期望看到:`kmod-tun`、`kmod-nft-tproxy`、`kmod-nft-socket`、`kmod-inet-diag`、`kmod-netlink-diag`、
`kmod-nft-nat`、`kmod-nft-fib`、`kmod-nf-reject`、`kmod-nf-reject6` 全部列出。

### ③ 顺手回归第二轮成果(不能被本轮回退)

```bash
dmesg | grep -i "supply vbus"     # 应【无输出】(有输出=VBUS 修复丢了)
usb-fix-check                     # 第二轮的一键自检,应仍在新固件里
```

### ④ 装 openclash / passwall

```bash
apk update
apk add luci-app-openclash
# 或者
apk add luci-app-passwall luci-i18n-passwall-zh-cn
```

若某台环境取不到包(或想离线),用交付的 apk(仅与本轮 ABI 匹配):

```bash
# 传到路由器 /tmp 后
apk add --allow-untrusted /tmp/kmod-tun-6.12.91-r1.apk    # 其余同理
```

启动:`/etc/init.d/openclash enable && /etc/init.d/openclash start`(或 LuCI → 服务 → OpenClash)

### ⑤ reboot 验证持久化(第二轮的血泪教训,不能省)

```bash
reboot
# 等 1~2 分钟
ping 192.168.1.1 && ssh root@192.168.1.1 'grep DISTRIB_REVISION /etc/openwrt_release; apk info | grep -c kmod-tun'
```

密码、版本、kmod 都还在 → 稳定可靠。(**永远先正常 `reboot` 验证,再考虑断电**——直接拔电容易损坏 overlay。)

### ⑥ 恢复第 0 步备份的配置(可选)

LuCI → 系统 → 备份/恢复 → 上传 `backup-*.tar.gz` 恢复并重启。

---

## 6. 阶段六:善后

- 想回退第二轮/官方:**TFTP 里把文件名改回对应的固件名再刷一次**;或 u-boot 恢复 `mtd5_ubi.bin` 备份。
- 救砖期间为验证而做的临时改动,记得还原:
  ```bash
  sudo nmcli radio wifi on                       # 若之前关了 WiFi
  sudo nmcli con mod recovery -ipv4.routes "192.168.1.1/32 0.0.0.0 50"   # 日常不再需要这条精确路由
  sudo sysctl -w net.ipv4.conf.eth0.rp_filter=2  # 或删除 /etc/sysctl.d/99-tftp-recovery.conf
  ```
- **别再断电拔插**:以后重启一律 `reboot`。
- 两个 `192.168.1.1` 撞车(路由器 vs 家里网关)是历史各种"诡异网络问题"的共同背景,建议把测试链路与日常链路分开。

---

## 附录 A:第二轮实战"病因 → 症状 → 解法"速查表

| # | 病因 | 当时看到的现象 | 解法(命令) |
|---|---|---|---|
| 1 | u-boot 请求的文件名和我们放的不一致 | 19 字节 UDP 回包 / 传输不开始 | 抓包看 RRQ 的确切文件名,把固件复制成那个名字 |
| 2 | **临时 `ip route add` 被 NetworkManager 刷新冲掉** | 加好的 `192.168.1.1/32` 路由过一会儿自己消失了 | `nmcli con modify recovery +ipv4.routes "192.168.1.1/32 0.0.0.0 50"` 持久化(变成 `proto static`) |
| 3 | **只有 metric 50 不够,被 wlan0 抢路** | `ip route get 192.168.1.1` 显示 `dev wlan0 src 192.168.1.165` | 显式 `src`:`ip route replace 192.168.1.1/32 dev eth0 src 192.168.1.254 metric 50`;并删掉 `192.168.1.0/24 dev eth0` 消除歧义 |
| 4 | **rp_filter=2 仍然丢包**(最关键的一条) | 路由已 `dev eth0 src 192.168.1.254`,服务正常、本机自测正常,但 RRQ 零回包 | `sudo sysctl -w net.ipv4.conf.eth0.rp_filter=0`(同时 default=0);改完立刻通了 |
| 5 | sysctl 不在 PATH | `zsh: command not found: sysctl` / 误在 Mac 上执行 | 在**树莓派**上用 `/sbin/sysctl`,或读 `/proc/sys/net/ipv4/conf/eth0/rp_filter` |
| 6 | tcpdump 旧窗口 | 看到的时间戳还是修复前的 | Ctrl+C 关掉,**重新开**一个再观察 |
| 7 | u-boot 重试超时后放弃 TFTP | 10 秒以上零新包;ping 通、SSH 进去发现还是旧版本号 | 重新走一遍"断电→等 20 秒→按住 Reset→插电→数到 20→松开" |
| 8 | 刷完 SSH 报 host key 变了 | `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` | `ssh-keygen -R 192.168.1.1` 后重连 |
| 9 | 两个 192.168.1.1(路由器 / 家里网关)撞车 | 各种静默失败、ARP 混乱 | 救砖时拔掉路由器 WAN 口那根上网线,保持点对点链路 |
| 10 | **本轮新增陷阱**:新旧固件同名同大小 | `ls -la` 看不出区别,`cp` 没覆盖也不会察觉 | 传完**必须** `sha256sum` 比对 `c8ff1c45…` |
| 11 | 交付说明里 hash 一句话写反了 | 文档说 `122562b1…` 是上一轮的 | 以自己 `grep ^kernel *.manifest` 为准(本轮=`122562b1…`,现网=`9981310e…`) |

### 第三轮实刷(2026-09-10)新增的坑,全部实测踩过

| # | 病因 | 当时看到的现象 | 解法(命令) |
|---|---|---|---|
| 12 | **Reset 按住时长不够** | 按 10 秒,两次都"一点反应没有" | 断电后**等 20 秒放电** + 按住 **20 秒**;改成这样就一次进恢复模式 |
| 13 | 用 `ping 192.168.1.1` 判断连通,测到的是**家里同 IP 的网关** | ping 通就以为链路没问题,其实走的是 wlan0 | 一律 `ping -I eth0 192.168.1.1`;配合 `ip neigh show dev eth0` 才作数 |
| 14 | 抓包窗口关掉/复用旧窗口 | 以为"没反应",其实是没在看新数据 | 用 `sudo nohup tcpdump -i eth0 -n -e > /tmp/boot.log 2>&1 &` 写文件,事后 `grep -c "length 1472"` 可数出 **10000** 个满包 |
| 15 | `apk info \| grep '^kernel'` 只输出包名 | 看不到内核 ABI 版本,以为验证失败 | 用 `apk list -I 2>/dev/null \| grep '^kernel'`,或 `grep -A1 '^P:kernel$' /lib/apk/db/installed` |
| 16 | **官方源被丢在 `distfeeds.list.bak`,`.list` 里顶的是死镜像** | `apk update` 报 `SSL error` / 取不到索引 | `cp distfeeds.list.bak distfeeds.list` 把官方源扶正;把 `.bak` 移出 `repositories.d` |
| 17 | **源里缺 `packages` feed** | `apk add luci-app-openclash` 报 `bash/curl/ruby/ruby-yaml/unzip (no such package)` | 补上一行 `.../packages/aarch64_cortex-a53/packages/packages.adb`(只配 base+luci 不够,9540 vs 4787 个包) |
| 18 | 家里网络与路由器 LAN 同为 `192.168.1.0/24`,**WAN 拿到地址也装不上默认路由** | `eth1` 有 `192.168.1.210/24`,但 `ip route` 只有 br-lan 那条、无 default | 改 LAN 网段:`uci set network.lan.ipaddr='192.168.2.1/24'`;**改之前先给树莓派 eth0 加新网段地址**免得被锁死 |
| 19 | OpenClash 核心不在 apk 包里 | 每次进 LuCI 都弹"您还未安装内核";`ps` 无进程 | Mac 下好 `clash-linux-arm64.tar.gz` → scp 进 `/tmp` → 解包后 `cp clash /etc/openclash/core/clash_meta && chmod +x`;`clash_meta -v` 应打印 `Mihomo Meta … with_gvisor` |
| 20 | 改 LAN 网段后 SSH "卡死" | `network reload` 后会话悬住 | 正常现象(br-lan 重建、TCP 失去对端),按 `~.` 强断或另开窗口,用新地址 `ssh root@192.168.2.1` |

## 附录 B:完整命令流水线(按顺序复制)

```bash
# ===== Mac:0. 备份现网配置 =====
ssh-keygen -R 192.168.1.1
ssh root@192.168.1.1 'sysupgrade -b /tmp/backup-$(date +%F).tar.gz'
scp -O root@192.168.1.1:/tmp/backup-*.tar.gz ~/Desktop/luyouqi/

# ===== Mac:1. 校验物料 =====
cd /Users/wt/Desktop/luyouqi/deliverables/firmware
shasum -a 256 *.itb *.manifest          # sysupgrade 必须 = c8ff1c45…

# ===== Mac:2. 传物料 =====
scp -O immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb mypi@192.168.1.165:/tmp/
scp -O /Users/wt/Desktop/luyouqi/pi-preflight-check.sh mypi@192.168.1.165:/tmp/

# ===== 树莓派:2b. 放进 TFTP 目录并校验 =====
ssh mypi@192.168.1.165
sudo cp /tmp/immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb /srv/tftp/
sudo chown root:root /srv/tftp/*.itb; sudo chmod 644 /srv/tftp/*.itb
sha256sum /srv/tftp/immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb   # c8ff1c45…

# ===== 树莓派:3. 环境自检(6 项,可一键) =====
sudo sh /tmp/pi-preflight-check.sh --fix
# 手工版:
sudo systemctl status tftpd-hpa --no-pager
sudo ss -ulnp | grep 69
ip addr show eth0; cat /sys/class/net/eth0/carrier
sudo nmcli con add type ethernet ifname eth0 con-name recovery ip4 192.168.1.254/24   # 若已存在会报错,忽略
sudo nmcli con modify recovery +ipv4.routes "192.168.1.1/32 0.0.0.0 50" && sudo nmcli con down recovery && sudo nmcli con up recovery && ip route show && ip route get 192.168.1.1
sudo sysctl -w net.ipv4.conf.eth0.rp_filter=0 && sudo sysctl -w net.ipv4.conf.default.rp_filter=0
sleep 45 && ip route get 192.168.1.1        # 复查:必须还是 dev eth0 src 192.168.1.254
tftp 192.168.1.254 -c get immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb /tmp/selftest.itb && ls -la /tmp/selftest.itb

# ===== 树莓派:4. 抓包(新开一个 SSH 会话,保持开着) =====
sudo tcpdump -i eth0 -n udp port 69
# 另一只手:断电 → 等 20 秒 → 按住 Reset → 插电 → 数到 20 → 松开
# 看到连续 1472 字节 DATA,最后一个小包(如 362 字节)= 传完

# ===== Mac:5. 刷完验证 =====
sleep 90; ping -c 3 192.168.1.1
ssh-keygen -R 192.168.1.1 && ssh root@192.168.1.1
# 路由器上:
passwd
grep DISTRIB_REVISION /etc/openwrt_release        # r37877-n30pro
uname -r                                          # 6.12.91
apk info | grep '^kernel'                         # 6.12.91~122562b1ee0c22b0eb77d2808e0bd84f
apk info | grep -E "kmod-(tun|nft-tproxy|nft-socket|inet-diag|netlink-diag|nft-nat|nft-fib|nf-reject)"
dmesg | grep -i "supply vbus"                     # 应无输出(第二轮成果不能丢)
apk update && apk add luci-app-openclash
reboot
```

## 附录 C:一键自检脚本

本仓库根目录已生成 `pi-preflight-check.sh`(只读检查;加 `--fix` 会自动做持久化路由 + rp_filter 修正):

```bash
scp -O /Users/wt/Desktop/luyouqi/pi-preflight-check.sh mypi@192.168.1.165:/tmp/
ssh mypi@192.168.1.165 'sudo sh /tmp/pi-preflight-check.sh'
# 全部 PASS 后,如果要让它顺手修环境:
ssh mypi@192.168.1.165 'sudo sh /tmp/pi-preflight-check.sh --fix'
```

---

## 附录 D:本轮实刷补遗(2026-09-10,全流程跑通后的记录)

### D.1 最终成功的动作序列(可照抄)

```bash
# ── 树莓派:起监视 ──
sudo pkill -f "tcpdump -i eth0" 2>/dev/null
sudo nohup tcpdump -i eth0 -n -e > /tmp/boot.log 2>&1 &
nohup sh -c 'while true; do echo "$(date +%T) carrier=$(cat /sys/class/net/eth0/carrier)"; sleep 1; done' > /tmp/carrier.log 2>&1 &

# ── 路由器:断电 → 等 20 秒 → 按住 Reset → 插电 → 数到 20 → 松开 → 等 60 秒 ──

# ── 树莓派:看结果 ──
cat /tmp/carrier.log
grep -vE "5353|ff02::|224\.0\.0\.(22|251)|ICMP6" /tmp/boot.log | tail -20
grep -c "length 1472" /tmp/boot.log        # 期望 10000(最后还有一个 358 字节尾包 → 线上 length 362)
```

**成功的现场长这样**(实测抓包):

```
22:30:13  carrier 1→0                                    ← 断电
22:30:58  carrier 0→1                                    ← 上电(按住 Reset 那 20 秒)
22:30:59.077  30:07:5c:71:3b:5e > ARP who-has 192.168.1.254 tell 192.168.1.1
22:30:59.077  RRQ "immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb"
22:30:59.078  192.168.1.254.54715 > 192.168.1.1.3325: UDP, length 1472      ← 开始灌
…（10000 个满包）
22:31:13  carrier 1→0 … 22:31:26 0→1 … 22:31:39 1       ← 写 flash + 重启
```

**传完就该变了的东西**:SSH host key 变了(`WYfHF+…` 而非旧值)、登录提示 `no root password defined`(配置被清空)、
`uname -r` = `6.12.91`、`apk list -I | grep '^kernel'` = `6.12.91~122562b1ee0c22b0eb77d2808e0bd84f-r1`。

### D.2 刷完的验收清单(本轮实测值)

| 检查 | 命令 | 期望 |
|---|---|---|
| 固件指纹 | `grep DISTRIB_REVISION /etc/openwrt_release` | `r37877-n30pro`(**二轮也是这个,单看它不够**) |
| 内核 ABI | `apk list -I \| grep '^kernel'` | `6.12.91~122562b1ee0c22b0eb77d2808e0bd84f-r1` |
| 新增 kmod | `apk info \| grep -E "kmod-(tun\|nft-tproxy\|nft-socket\|inet-diag\|netlink-diag\|nft-nat\|nft-fib\|nf-reject)"` | 9 个全在 |
| 模块实体 | `ls /lib/modules/$(uname -r)/ \| grep -E "^(tun\|nft_tproxy\|nft_socket\|nft_nat\|nf_reject_ipv4\|inet_diag\|netlink_diag)\.ko"` | 全在 |
| 二轮成果 | `dmesg \| grep -i "supply vbus"` | **无输出** |
| 持久化 | `reboot` 后再看密码/内核/包 | 全都在 |

### D.3 装 openclash 的完整避坑链

```sh
# 1) 源:把官方源从 .bak 扶正,并补 packages feed
cp /etc/apk/repositories.d/distfeeds.list.bak /etc/apk/repositories.d/distfeeds.list
mv /etc/apk/repositories.d/distfeeds.list.bak /root/
echo "https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/packages/packages.adb" \
     >> /etc/apk/repositories.d/distfeeds.list
grep -v '^#' /etc/apk/repositories.d/distfeeds.list     # 应有 4 行

# 2) 装(33 个包,约 62.7 MiB)
apk update && apk add luci-app-openclash

# 3) 核心:路由器自己下不动 GitHub,从 Mac/树莓派离线塞进去
#    Mac: scp -O /tmp/clashcore/clash-linux-arm64.tar.gz root@192.168.2.1:/tmp/
cd /tmp && tar xzf clash-linux-arm64.tar.gz
mkdir -p /etc/openclash/core && cp /tmp/clash /etc/openclash/core/clash_meta
chmod +x /etc/openclash/core/clash_meta
/etc/openclash/core/clash_meta -v      # 期望:Mihomo Meta alpha-… linux arm64 … with_gvisor
```

核心 tarball 校验值(实测):`sha256 = 8252d16726041872825cdd9089c798c318f8862466b40b34d8bf62225ef57e34`
(Meta 核心 arm64;解包后是单个 `clash` 文件,`Mihomo Meta alpha-ge183c58`,`with_gvisor` = 支持 TUN)。

### D.4 现场拓扑与固定参数(照此复现)

| 项 | 值 |
|---|---|
| Mac | 有线 `en7` = `192.168.2.212`(直连路由器时);WiFi 时 `192.168.1.201` |
| 树莓派 | `mypi@192.168.1.165`(WiFi);eth0 同时挂 `192.168.1.254/24` + `192.168.2.254/24` |
| 路由器 | LAN 改为 **`192.168.2.1`**(原 `192.168.1.1`);WAN = `eth1`,从家里拿 `192.168.1.x` |
| **u-boot 救砖** | **永远 `192.168.1.1`**;树莓派那条 `192.168.1.1/32 dev eth0 src 192.168.1.254 metric 50` **必须一直留着** |
| 网线接的口 | 路由器 **lan2**(实测 TFTP 就是在这个口成功的,救砖别换口) |
| 家里网络 | 也是 `192.168.1.0/24`、网关 `192.168.1.1`,且**在跑 fake-IP 代理**(DNS 透明劫持,连指 223.5.5.5 也返回 `198.18.x.x`) |

> fake-IP 的副作用要记住:`ping www.baidu.com` 会解析成 `198.18.0.41` 这类假 IP,**ICMP 不通是正常的**,
> 不代表没网——判断连通看 `ping 223.5.5.5` 和 `ip route` 里的 default 路由。

## 附录 E:OpenClash 实配与排错(2026-09-11 实测通过)

### E.1 最终验收(从 LAN 客户端 Mac 实测)

```
DNS(经路由器)   www.google.com → 198.18.0.9            ← fake-IP 生效
出口 IP          132.145.56.31 (Oracle Cloud, Slough/GB) ← 流量真的从代理服务器出去
google           HTTP/2 200
wikipedia        HTTP/2 200
```

对照第三轮交付说明第六节:**google/wikipedia 在 TProxy/Redirect 下全通 → 当初"部分站点静默卡死"
确认是旧固件缺 `kmod-tun`/`kmod-nft-tproxy` 所致,问题闭环。**

### E.2 两个致命陷阱(都会让"整个路由器 + 局域网都没网")

**陷阱 1:上游 DNS 自环。** OpenClash 启动时会重写配置的 `dns` 段(日志里的 `Step 3: Modify The Config File`),
把 `nameserver` 换成 `dhcp://"<WAN口>"` + `<LAN地址>`,于是解析链变成:

```
核心解析服务器域名 → 问 192.168.2.1(自己)→ dnsmasq 被劫持 → 转回核心 7874 → 返回 fake-IP → 拿假 IP 去连 → 超时
```

症状:`dial ... error: dial tcp 198.18.0.x:443: i/o timeout`、`interface not found`、
`read udp 192.168.2.1:53: connection refused`、`Sync time failed`。

**修法:启用 OpenClash 自带的真实 DNS 池**(改 yaml 没用,启动时会被覆盖):

```sh
uci set openclash.config.enable_custom_dns='1'
uci commit openclash
```

改完运行时配置里会出现 `114.114.114.114 / 119.29.29.29 / https://doh.pub/dns-query / dns.alidns.com`。

**陷阱 2:fake-IP 毒化代理服务器域名。** 配置里 `server:` 写域名时,该域名也会被解析成 fake-IP
(`198.18.0.5`),核心拿假 IP 去连自己的服务器 → 必然超时。

**修法(最省事):把 `server:` 直接写成真实 IP,`sni:` 保留域名:**

```sh
nslookup vip.xpspdf.lat 223.5.5.5      # 先查出真实 IP,例:132.145.56.31
sed -i 's|^  server: <你的域名>|  server: <真实IP>|' /etc/openclash/config/<配置>.yaml
```

(等价做法:保留域名 + 在 `fake-ip-filter` 里加 `+.你的域名`;但 OpenClash 会重写 dns 段,
不如直接写 IP 稳。)

### E.3 如果 OpenClash 又把全网掐断了(急救三行)

```sh
uci set openclash.config.enable='0'; uci commit openclash; /etc/init.d/openclash stop; sleep 5; ping -c 2 -W 2 223.5.5.5
```

> 记得**同时把 enable 置 0**:OpenClash 有看门狗(`openclash_watchdog.sh`),只 `stop` 可能被它拉起来。
> 另外:`ping/nslookup` 通不代表 DNS 好使——路由器上可以用 `nslookup www.baidu.com 223.5.5.5` 直接对公共 DNS 验证。

### E.4 诊断用的三把快刀

```sh
# ① 配置能不能被核心接受(不启动只校验;注意 dns 段里的 external-ui 路径会让校验误报,先删掉那行)
mkdir -p /tmp/oc-test
sed '/^external-ui:/d' /etc/openclash/config/<配置>.yaml > /tmp/oc-test/t.yaml
/etc/openclash/core/clash_meta -d /tmp/oc-test -f /tmp/oc-test/t.yaml -t

# ② 看【本次启动之后】的日志(别被旧记录骗了,核对时间戳)
tail -40 /tmp/openclash.log

# ③ 显式走 HTTP 端口,绕开 nftables 透明重定向,单独测节点
curl -s --max-time 20 -x http://Clash:<日志里查到的密码>@192.168.2.1:7890 https://api.ip.sb/geoip
```

**②③ 的判别法**:显式能通、透明不通 → 问题在 nftables 重定向;两条都不通 → 问题在节点本身(密码/sni/端口)。

### E.5 现场最终状态(照此复现)

| 项 | 值 |
|---|---|
| WAN | **`eth2` = 中兴 F50**(USB),地址 `192.168.0.184`,网关 `192.168.0.1` |
| LAN | `br-lan` = `192.168.2.1/24`;Mac 直连 `en7` = `192.168.2.212` |
| OpenClash | `luci-app-openclash 0.47.156`;核心 `clash_meta`(Mihomo Meta,`with_gvisor`);运行模式 `fake-ip` + nftables 重定向 |
| 持久化 | `/etc/rc.d/S99openclash` 存在,`enable=1`,重启后自动起 |

> 小无害告警:`tail: can't open '/etc/crontabs/root'` —— 系统还没建过 crontab,OpenClash 想加定时任务而已。
> 想消掉:`touch /etc/crontabs/root && /etc/init.d/cron restart`。

## 一句话总结

**"刷不上"几乎从来不是固件的问题,而是树莓派侧"TFTP 回包发不出去"**:
先保 `ip route get 192.168.1.1 → dev eth0 src 192.168.1.254`(nmcli 持久化 + 显式 src),
再把 `rp_filter` 压到 `0`(2 也不行),这两条都过了,最后**断电等 20 秒 + 按住 Reset 20 秒**,基本一次成功。
