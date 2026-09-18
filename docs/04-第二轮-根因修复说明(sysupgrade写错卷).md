# 第二轮交付:USB 供电修复固件(含根因修复)

> 本轮针对你上一份《验证反馈报告》做了**产物级复核**,结论是:
> **上次刷机没有真正生效** —— 不是 DTS 写错,而是这台设备在系统内 `sysupgrade` 时
> 走错了升级分支。本轮已修复该问题,并新增自检工具。

---

## 一、根因结论(有证据,可自查)

### 1. 上次那份固件根本没被引导起来

| 证据 | 你设备实际值 | 本交付固件应有的值 |
|---|---|---|
| `/etc/openwrt_release` 里的 `DISTRIB_REVISION` | `r37877-3c71dfc2b6`(V2 的) | **`r37877-n30pro`** |
| `apk info \| grep usb` | 6 个(旧 V2 的包集) | **12 个 + usbfix** |
| 实时设备树是否有 `vbus-supply` | 无(所以日志报 `supply vbus not found`) | 有 |

我这份镜像里**确实**有 `vbus-supply`(我已用 dtc 反编译交付文件确认:pio 节点 phandle `0x0a`、
GPIO 号 `0x17`=23、flags `0x00`=高有效、`vbus-supply` 指向 `phandle 0x20` = `regulator-usb-vbus`)。
内核日志报 `supply vbus not found` 只能说明:**内核当时用的 DTB 里没有这个属性,即运行的还是旧系统。**

### 2. 为什么"刷机成功"却没生效

这台设备身份是 `netcore,n30pro`(DTS compatible),而这份源码
`target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh` 的两份白名单里:

* `platform_do_upgrade()` → `fit_do_upgrade` 白名单:**有 `netis,nx30v2`,没有 `netcore,n30pro`**
* `platform_check_image()` 同上

于是系统内 `sysupgrade` 落到兜底分支 `nand_do_upgrade`,而它默认 `CI_KERNPART=kernel`:

* 它把镜像写进了名为 **`kernel`** 的 UBI 卷(甚至可能是新建的);
* 而 u-boot 的引导命令是 `boot_nand=ubi read $loadaddr fit; bootm $loadaddr#config-1`
  —— **只从 `fit` 卷引导**(来自 u-boot 默认环境 `defenvs/netis_nx30v2.env`);
* 结果:sysupgrade 返回成功、配置被保留(`rootfs_data` 未动)、重启后依旧跑旧固件。

**本轮修复**:把 `netcore,n30pro` 加入这两份白名单 → `fit_do_upgrade` 会通过
`chosen/rootdisk` 自动解析出正确的卷名(`fit`)再写入。

---

## 二、本轮改动清单

| 文件 | 改动 | 目的 |
|---|---|---|
| `.../lib/upgrade/platform.sh` | 两份白名单加入 `netcore,n30pro` | **让系统内 sysupgrade 真正写进 `fit` 卷**(根因修复) |
| `.../dts/mt7981b-netcore-n30pro.dts` | 新增 `usb_vbus`(GPIO23/高有效/5V)+ `regulator-boot-on` + `regulator-always-on`;`&xhci` 挂 `vbus-supply` | USB VBUS 供电;`always-on` 为双保险,不依赖驱动使能顺序 |
| `.../image/filogic.mk` | `DEVICE_PACKAGES` 增补 USB 网络共享驱动 + luci + `usbfix` | F50 识别所需的 cdc_ether/rndis/cdc_ncm/acm 等 |
| `.../board.d/02_network` | `netcore,n30pro` → LAN=lan1~lan4,WAN=eth1 | 全新安装时不会把 WAN 指到不存在的 `wan` 设备 |
| 新增本地包 `package/utils/usbfix` | 安装 `/usr/sbin/usb-fix-check`、`/etc/usb-fix-id` | **一键自检**,下轮反馈只需贴它的输出 |

---

## 三、交付文件

`firmware/` 目录:

| 文件 | 说明 |
|---|---|
| `immortalwrt-mediatek-filogic-netcore_n30pro-squashfs-sysupgrade.itb` | 主固件,14,680,358 字节<br>sha256 `c8ff1c45b053680261074e5faa41c7d25b653004154c7b86af4c6775e5af3eb7` |
| `immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb` | **同一文件,按你 u-boot 的 `bootfile_fw` 预改名** —— TFTP 整刷直接用这个 |
| `immortalwrt-mediatek-filogic-{netcore_n30pro,netis_nx30v2}-initramfs.itb` | 救援/内存系统版本 |
| `*.manifest` | 固件内包清单 |

> 两个 sysupgrade 文件内容完全相同,只是文件名不同(方便 TFTP 与系统内两条路)。

---

## 四、刷机方式(推荐顺序)

### 方式 1(最稳):u-boot TFTP 整刷 —— 与升级脚本无关,一定写进 `fit` 卷

1. TFTP 目录放 **`immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb`**
   (即上面预改名的那个,名字必须完全一致,可用 `sudo tcpdump -i eth0 -n udp port 69` 复核 u-boot 请求的 RRQ 名);
2. 路由器断电 → 按住 Reset → 上电保持约 10 秒 → 松开;
3. u-boot 会自动 `tftpboot` 该文件并执行
   `ubi remove fit; ubi create fit; ubi write ...` → 等待 led 停止闪烁后自动重启;
4. 起不来或想重来:重复步骤 2。

> 你的 u-boot 环境里 `upgrade_fw` 正是这条路径,因此这条路**不依赖**本轮 platform.sh 修复。

### 方式 2:系统内 sysupgrade(本轮已修好)

```sh
scp -O ./firmware/immortalwrt-mediatek-filogic-netcore_n30pro-squashfs-sysupgrade.itb root@192.168.1.1:/tmp/
ssh root@192.168.1.1
sha256sum /tmp/immortalwrt-mediatek-filogic-netcore_n30pro-squashfs-sysupgrade.itb   # 必须等于 d6367645...
sysupgrade /tmp/immortalwrt-mediatek-filogic-netcore_n30pro-squashfs-sysupgrade.itb
```

---

## 五、刷完请先确认"这次真的生效了"

```sh
grep DISTRIB_REVISION /etc/openwrt_release     # 必须是 r37877-n30pro
cat /etc/usb-fix-id                            # 必须存在
usb-fix-check                                  # 一键自检(推荐把输出整体贴回)
```

`usb-fix-check` 会打印:固件指纹、实时设备树里 `regulator-usb-vbus` / `vbus-supply` 是否存在、
regulator 列表、GPIO 状态、UBI 卷、USB 内核日志、USB 驱动包清单、当前 USB 设备与网卡。

**USB 供电是否修好的判断**:插上设备(或空载测 USB 口 5V),若设备指示灯亮/能枚举,
并且 `dmesg | grep -i "supply vbus"` **无输出** → 修复生效。

---

## 六、如果这次 USB 还是不上电

按下面顺序给我信息,我据此定位(不需要盲刷):

1. `usb-fix-check` 的完整输出;
2. 若脚本显示 `regulator-usb-vbus` 存在但 GPIO 23 不是 `out hi`,说明引脚不对;
3. 备选实验(告诉我结论即可,我可以出专门的诊断固件):
   - 用 `echo 23 > /sys/class/gpio/export` 尝试手动拉高(若报 busy,说明已被 regulator 占用,属正常);
   - 若 23 无效,则在该 ODM 家族里另有两个候选思路:GPIO13(社区固件里是 USB 指示灯,通常不是电源)、
     以及需要按 PCB 实测确认的其他引脚 —— 我会出一个"逐引脚试探"的诊断固件(带 `gpioset` 与脚本),
     你在真机上直接找出真正控制 VBUS 的引脚,再定版。
