# 第三轮交付:补齐 openclash / passwall 所需内核模块

上一轮反馈(USB 供电 + F50)已确认通过 ✅。本轮按你的《missing-kmod-modules-request.md》
补齐缺失内核模块。

---

## 一、为什么仓库里"根本找不到"这些包(根因)

不是镜像源没配全,而是**这几个内核模块在上游默认编译配置里就不编译**:

* 这些 kmod 的 Kconfig 符号默认是 `DEFAULT:=m if ALL_KMODS` —— 即**只有开了 `CONFIG_ALL_KMODS`(编译全部内核模块)才会生成**;
* 官方发布的 `kmods` 仓库是按官方内核配置编的,官方没勾 = 仓库里就没有这个条目,所以你 `apk search` 全空;
* 更关键的一点:**内核模块与内核 ABI 是绑死的**。你的设备跑的是我们自编译内核
  (`kernel=6.12.91~<本机内核配置哈希>`),即使官方仓库里有 `kmod-tun`,其依赖的 `kernel=...` 也对不上,装不上。
  → 所以这类模块**只能由本固件自带**,这也正是本次的做法。

---

## 二、本轮编译进固件的内核模块

| 模块 | 用途 | 来源 |
|---|---|---|
| `kmod-tun` | TUN/TAP 虚拟网卡(clash / sing-box 的 TUN 模式) | 你清单 |
| `kmod-nft-tproxy` | nftables TPROXY 透明代理 | 你清单 |
| `kmod-nft-socket` | nftables socket 匹配(配合 tproxy) | 你清单 |
| `kmod-inet-diag` | inet 连接诊断(sing-box 查连接状态) | 你清单 |
| `kmod-netlink-diag` | netlink 诊断 | 你清单 |
| `kmod-nft-nat` | nftables NAT(passwall 依赖) | passwall 依赖 |
| `kmod-nf-reject` / `kmod-nf-reject6` | nft reject(passwall 依赖) | passwall 依赖 |
| `kmod-nft-fib` | nft `fib` 表达式(代理规则常用) | 预防性补齐 |

配套的依赖模块(`kmod-nft-core`、`kmod-nf-tproxy`、`kmod-nf-socket`、`kmod-nf-nat`、
`kmod-nf-conntrack`、`kmod-ipt-*` 等)由包管理自动解析并已一并装入。

> 说明:一度也加了 `kmod-ipt-tproxy`(iptables 版 TPROXY),但它会拖出整条 iptables 内核模块链,
> 而 openclash/passwall 现在默认走 nftables,故最终**未纳入**;如你确实需要 iptables 模式,告诉我再加。

**产物已逐项验证**(从 .itb 内 rootfs 解包核对):
`tun.ko`、`nft_tproxy.ko`、`nft_socket.ko`、`nft_nat.ko`、`nft_fib*.ko`、
`nf_reject_ipv4/ipv6.ko`、`inet_diag.ko`、`netlink_diag.ko`、`tcp_diag.ko`、`udp_diag.ko`、`raw_diag.ko`
均已存在;apk 数据库中 `kmod-tun` / `kmod-nft-tproxy` / `kmod-nft-socket` /
`kmod-inet-diag` / `kmod-netlink-diag` / `kmod-nft-nat` / `kmod-nft-fib` /
`kmod-nf-reject` / `kmod-nf-reject6` 均为已安装状态。

---

## 三、⚠️ 必须整机刷入(不能只装 kmod 包)

本轮为了打开这些模块,**内核配置发生了变化**,导致内核包版本哈希从
`6.12.91~122562b1ee0c22b0eb77d2808e0bd84f`(上一轮镜像)变为本轮的新哈希。
因此:

* 这些 kmod 的 `.apk` **无法安装到上一轮固件上**(ABI 不匹配),必须刷本轮整机镜像;
* 刷机方式与上一轮相同(推荐 u-boot TFTP 整刷,文件名用
  `immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb`;系统内 `sysupgrade` 现在也是修好的)。

## 四、交付文件

`firmware/`:

| 文件 | 说明 |
|---|---|
| `immortalwrt-mediatek-filogic-netcore_n30pro-squashfs-sysupgrade.itb` | 主固件,sha256 `c8ff1c45b053680261074e5faa41c7d25b653004154c7b86af4c6775e5af3eb7` |
| `immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb` | 同一文件、按 u-boot `bootfile_fw` 预改名(TFTP 用) |
| `...-{netcore_n30pro,netis_nx30v2}-initramfs.itb` | 救援/内存系统 |
| `kmods-apk/` | 本次新增 kmod 的 `.apk`(离线备用;仅与本轮内核 ABI 匹配) |
| `*.manifest` | 固件内包清单 |

仍包含上一轮的全部内容:USB VBUS 供电修复、F50 的 usb-net 驱动、`usbfix` 自检、LuCI 中文。

---

## 五、刷完后怎么装 openclash / passwall

```sh
# 1) 先确认刷的是本轮固件
grep DISTRIB_REVISION /etc/openwrt_release      # r37877-n30pro
uname -r                                        # 6.12.91
apk info | grep -E "kmod-(tun|nft-tproxy|nft-socket|inet-diag|netlink-diag)"   # 应全部列出

# 2) 更新源后安装(依赖应已满足,不再报"未提供")
apk update
apk add luci-app-openclash
# 或
apk add luci-app-passwall luci-i18n-passwall-zh-cn
```

若某台环境仍然取不到包(或想离线装),可用交付的 apk:

```sh
# 传到路由器 /tmp 后
apk add --allow-untrusted /tmp/kmod-tun-6.12.91-r1.apk   # 其余同理(本机 ABI 匹配时才可用)
```

安装后按需重启:`/etc/init.d/openclash enable && /etc/init.d/openclash start`
(或 LuCI → 服务 → OpenClash)。

---

## 六、关于你提到的"REDIRECT 模式下部分网站卡死"

那是上一轮(缺 tun/tproxy)时用 xray REDIRECT 模式的临时方案现象,**与本轮补齐模块的问题相互独立**。
现在有了 `kmod-tun` + `kmod-nft-tproxy`,建议改用 **OpenClash 的 TUN / TProxy 模式**再测一次:

* 若 TUN/TPROXY 下 google/wikipedia 正常 → 说明是 REDIRECT 模式的局限,问题闭环;
* 若仍然只有部分站点静默超时(注意:你能开 bing,却卡 google/wikipedia,同时另一台设备同节点正常),
  主要可疑方向是 **DNS 解析/Fake-IP 未生效** 与 **MTU/MSS**(你已做 1350 的 MSS clamp,
  可再试 1280,或直接开 OpenClash 的"自定义 DNS + Fake-IP"),把 OpenClash 的运行模式、DNS 设置、
  `nft list ruleset` 与 F50 接口的 MTU 一并反馈,我们下一轮定位。

---

## 七、本轮改动清单(源码层面)

| 文件 | 改动 |
|---|---|
| `target/linux/mediatek/image/filogic.mk` | `Device/netcore_n30pro` 的 `DEVICE_PACKAGES` 增加上表 kmod |
| 构建用 `.config` | 显式打开 `CONFIG_PACKAGE_kmod-tun`、`kmod-nft-tproxy`、`kmod-nft-socket`、`kmod-nf-tproxy`、`kmod-nf-socket`、`kmod-inet-diag`、`kmod-netlink-diag`(这几个符号默认不选,必须显式打开,这也是官方仓库缺包的根因) |
| 清理重建 | 内核配置变化后,`package/kernel/{linux,mt76,mac80211,gpio-button-hotplug}` 与 `fullconenat-nft` 需 clean 后重编,否则旧 ABI 的 kmod 与新 kernel 冲突(报 `breaks:`),本轮已处理 |

补丁见 `patches/`,其中 `filogic-mk-device-packages.patch` 已更新为最新内容。
