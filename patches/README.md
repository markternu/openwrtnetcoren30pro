# 补丁说明

源码基线:**`SamZong233/immortalwrt` commit `3c71dfc2b6`**(ImmortalWrt 25.12-SNAPSHOT,内核 6.12.91,
即设备上原 V2 固件的同源代码)。所有补丁都可用 `scripts/apply-patches.sh` 一键应用。

| 文件 | 目标 | 作用 |
|---|---|---|
| `target-dts-mt7981b-netcore-n30pro.dts` | `target/linux/mediatek/dts/` | **最终设备树全文**(直接覆盖)。核心:新增 `usb_vbus` — GPIO23、高有效、5V、`regulator-boot-on` + `regulator-always-on` 的 fixed-regulator,并给 `&xhci` 挂 `vbus-supply` → 修复 USB 口无 5V 供电 |
| `target-dts-usb-vbus.patch` | 同上 | 便于 review 的 diff 形式 |
| `target-image-filogic.mk.patch` | `target/linux/mediatek/image/filogic.mk` | `Device/netcore_n30pro` 的 `DEVICE_PACKAGES` 增补内容(见下表) |
| `upgrade-platform.sh.patch` | `target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh` | **根因修复**:把 `netcore,n30pro` 加进 `platform_do_upgrade()` / `platform_check_image()` 的 `fit_do_upgrade` 白名单。否则系统内 `sysupgrade` 落到兜底分支(`CI_KERNPART=kernel`)写错 UBI 卷,表现为"刷机成功但没生效" |
| `board.d-02_network.patch` | `.../filogic/base-files/etc/board.d/02_network` | 为 `netcore,n30pro` 补默认映射:LAN=`lan1~lan4`,WAN=`eth1`(否则落到兜底分支,把 WAN 指向不存在的 `wan` 设备 → "刷完没网") |
| `build-base-files-apk-version.patch` | `package/base-files/Makefile` | 编译期修补:该 fork 用 **apk** 打包,`VERSION:=$(PKG_RELEASE)~$(REVISION)` 里的 `~` 被 apk 判为非法版本号 → 改为 `$(PKG_RELEASE)-r1` |
| `build-cgi-io-Makefile.txt` | `package/net/cgi-io/Makefile` | `luci-base` 依赖 `cgi-io`,而它在 packages feed 里;此处只放单包 Makefile,避免克隆整个 feed |

### `DEVICE_PACKAGES` 增补内容

```
# USB 网络共享(中兴 F50 / 手机 tethering)
kmod-usb-storage-uas kmod-usb-net kmod-usb-net-cdc-ether
kmod-usb-net-rndis kmod-usb-net-cdc-ncm kmod-usb-acm block-mount

# Web 界面(含中文)
luci luci-ssl luci-i18n-base-zh-cn luci-theme-bootstrap

# 代理应用(openclash / passwall)所需内核模块
kmod-tun kmod-nft-tproxy kmod-nft-socket kmod-nft-nat
kmod-nf-reject kmod-nf-reject6 kmod-inet-diag kmod-netlink-diag
kmod-nft-fib

# 本项目自检工具
usbfix
```

> ⚠️ 这些 kmod 的 Kconfig 符号默认是 `DEFAULT:=m if ALL_KMODS`,**只加进 `DEVICE_PACKAGES` 不够**,
> 还必须显式写进 `.config`(`scripts/build.sh` 已处理),否则不会被编译 —— 这正是官方仓库里
> 找不到 `kmod-tun` / `kmod-nft-tproxy` 等包的原因。
