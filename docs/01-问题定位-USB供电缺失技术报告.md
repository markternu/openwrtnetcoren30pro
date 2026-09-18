# Netcore N30 Pro (netis_nx30v2) USB 供电缺失问题技术报告

## 1. 设备信息

| 项目 | 内容 |
|---|---|
| 设备型号 | Netcore N30 Pro(同一硬件平台亦被称为 Netis NX30V2 / Netcore POWER30AX / GWBN GW3001 / GLC W7) |
| SoC平台 | MediaTek Filogic(mediatek/filogic target) |
| 架构 | aarch64_cortex-a53 |
| Bootloader | ImmortalWrt 官方 u-boot(`immortalwrt-25.12.0-mediatek-filogic-netis_nx30v2-spim-nand-bl31-uboot.fip`),已刷入替换原厂bootloader,当前为无WebUI版本 |
| 存储 | SPI-NAND |
| 当前固件来源 | 第三方编译:[SamZong233/immortalwrt](https://github.com/SamZong233/immortalwrt) release tag `NetCore_N30_Pro_FW_V2`,文件 `n30pro-squashfs-lite.itb` |
| 固件版本 | ImmortalWrt 25.12-SNAPSHOT, r37877-3c71dfc2b6 |

## 2. 问题背景

上游官方 OpenWrt/ImmortalWrt 对该设备(netis_nx30v2)的适配存在已知缺陷:错误地复用/强行合并了 Netis 某型号的分区表与设备树,导致:
- 缺少一个 LAN 口(官方版本只识别出部分网口)
- USB 接口完全无法使用(未识别或无法正常工作)

第三方开发者 SamZong233 重新制作了该设备的 DTS(设备树),发布于其 GitHub release `NetCore_N30_Pro_FW_V2`,号称已解决"识别问题、网口缺少、USB问题"。

## 3. 已验证修复的部分

刷入 SamZong233 编译的固件(`n30pro-squashfs-lite.itb`)后,通过 `ip link show` 验证:

```
2: eth0: ... UP ...
3: eth1: ... (NO-CARRIER) ...
4: lan1@eth0 ...
5: lan2@eth0 ... UP ...
6: lan3@eth0 ...
7: lan4@eth0 ...
8: lan5@eth0 ...
```

**结论:5个LAN口(lan1~lan5)全部被正确识别**,较官方版本"缺少一个LAN口"的问题已解决。

## 4. 未解决问题:USB 端口无供电

### 4.1 现象描述

- physically 插入 USB 设备(测试设备:中兴 F50 CPE)后,**设备完全无供电反应**(设备指示灯不亮,无任何启动迹象)
- 内核层面 USB 主控制器(xHCI)已被正确识别,USB总线注册成功,但没有检测到任何设备插入事件

### 4.2 内核诊断信息

```
$ ls /sys/bus/usb/devices/
1-0:1.0  2-0:1.0  usb1  usb2
```
(仅有两条总线自身的hub,没有任何下游设备被枚举)

```
$ cat /sys/kernel/debug/usb/devices
T: Bus=01 Lev=00 Prnt=00 Port=00 Cnt=00 Dev#= 1 Spd=480  MxCh= 1
D:  Ver= 2.00 Cls=09(hub  ) Sub=00 Prot=01 MxPS=64 #Cfgs=  1
P:  Vendor=1d6b ProdID=0002 Rev= 6.12
S:  Manufacturer=Linux 6.12.91 xhci-hcd
S:  Product=xHCI Host Controller
C:* #Ifs= 1 Cfg#= 1 Atr=e0 MxPwr=  0mA
I:* If#= 0 Alt= 0 #EPs= 1 Cls=09(hub  ) Sub=00 Prot=00 Driver=hub

T: Bus=02 Lev=00 Prnt=00 Port=00 Cnt=00 Dev#= 1 Spd=10000 MxCh= 1
D:  Ver= 3.10 Cls=09(hub  ) Sub=00 Prot=03 MxPS= 9 #Cfgs=  1
P:  Vendor=1d6b ProdID=0003 Rev= 6.12
S:  Manufacturer=Linux 6.12.91 xhci-hcd
S:  Product=xHCI Host Controller
C:* #Ifs= 1 Cfg#= 1 Atr=e0 MxPwr=  0mA
I:* If#= 0 Alt= 0 #EPs= 1 Cls=09(hub  ) Sub=00 Prot=00 Driver=hub
```

关键内核启动日志(dmesg):

```
[    1.752868] phy phy-soc:usb-phy@11e10000.1: type_sw - reg 0x218, index 0
[    2.774535] usbcore: registered new interface driver usbfs
[    2.780135] usbcore: registered new interface driver hub
[    2.785483] usbcore: registered new device driver usb
[    2.803734] xhci-mtk 11200000.usb: supply bus not found, using dummy regulator
[    2.811908] xhci-mtk 11200000.usb: xHCI Host Controller
[    2.817150] xhci-mtk 11200000.usb: new USB bus registered, assigned bus number 1
[    2.827582] xhci-mtk 11200000.usb: hcc params 0x01403f99 hci version 0x110 quirks 0x0000000000200010
[    2.836766] xhci-mtk 11200000.usb: irq 84, io mem 0x11200000
[    2.842530] xhci-mtk 11200000.usb: xHCI Host Controller
[    2.847759] xhci-mtk 11200000.usb: new USB bus registered, assigned bus number 2
[    2.855149] xhci-mtk 11200000.usb: Host supports USB 3.2 Enhanced SuperSpeed
[    2.862627] hub 1-0:1.0: USB hub found
[    2.870662] usb usb2: We don't know the algorithms for LPM for this host, disabling LPM.
[    2.879297] hub 2-0:1.0: USB hub found
[    2.893412] usbcore: registered new interface driver usb-storage
```

已加载的相关内核模块:
```
$ lsmod | grep -i usb
usb_common    12288  3 xhci_plat_hcd,xhci_hcd,usbcore
usb_storage   57344  0
usbcore      196608  5 usb_storage,xhci_plat_hcd,xhci_pci,xhci_mtk_hcd,xhci_hcd
```

### 4.3 根因定位

**关键行**:
```
xhci-mtk 11200000.usb: supply bus not found, using dummy regulator
```

这表明:
1. xHCI 主控制器驱动(`xhci-mtk`)本身**已经正确加载并识别了硬件**(USB2.0总线 + USB3.0总线均注册成功,支持USB 3.2 Enhanced SuperSpeed)
2. 但内核在初始化时尝试查找名为 `bus`(或类似)的 **regulator(电源调节器)供电节点**,在设备树(DTS)中**未找到对应定义**,因而退回使用一个"dummy regulator"(空占位电源),该占位电源**不会真正给USB VBUS供电**
3. 因此 USB 口物理层面完全没有 5V VBUS 电压输出,导致任何插入的USB设备都无法获得电力,不会有任何插入检测/枚举行为

**结论:这是设备树(DTS)配置缺陷,不是驱动缺失或内核配置问题。控制器驱动与内核USB子系统均工作正常,唯独缺少VBUS供电的regulator节点定义(或该节点定义存在但未正确关联到GPIO/PMIC供电引脚)。**

## 5. 需要的修复方向(供开发者/AI工具参考)

需要在该设备的 DTS 文件中,为 USB 主控制器节点(`11200000.usb`,对应 xhci-mtk)补充或修正供电相关的 regulator 定义,通常需要以下几类修改之一或组合:

1. **添加 `usb-vbus-supply` / `vbus-supply` 属性**,并在DTS中定义一个 `fixed-regulator` 或关联到 PMIC 的实际supply 节点,指向控制USB口供电的GPIO引脚
2. **确认PCB硬件层面USB口供电的实际GPIO引脚号**(需要参考原厂硬件资料或者对比同SoC平台、已知USB供电正常工作的其他Filogic设备DTS作为参照,例如小米 WR30U、H3C NX30 Pro 等同平台设备的DTS中USB供电相关定义)
3. 如果该GPIO本身默认就是拉高供电、只是DTS里没声明,也可能只需添加一个简单的 `fixed-regulator` 节点,default state 设为 enabled,不需要额外的GPIO控制逻辑

### 建议的具体排查/修复步骤

1. 查找该设备当前DTS源文件路径,通常位于 OpenWrt/ImmortalWrt 源码树:
   `target/linux/mediatek/dts/mt7981b-netcore-n30-pro.dts` 或类似命名(SamZong233 fork中路径可能不同,需要在其GitHub仓库源码中搜索 `netis_nx30v2` 或 `n30pro` 相关dts/dtsi文件)
2. 对比同平台(mediatek/filogic, 特别是同样搭载MT7981/MT7986系列SoC)且USB供电正常的其他设备DTS,例如:
   - Xiaomi Mi Router WR30U
   - H3C Magic NX30 Pro(与本设备为同一硬件ODM,极可能DTS高度相似甚至通用)
   - 查找这些设备DTS中 `usb` 节点下 `vbus-supply` 或类似regulator定义,对照添加到本设备DTS
3. 确认硬件层面USB供电控制引脚(如果有实体开发板资料/原厂SDK更佳;没有的话可尝试参考同ODM厂商其他型号的公开DTS作为强参考)
4. 修改后重新编译固件(sysupgrade格式或initramfs均可),刷入测试,验证 `dmesg | grep usb` 中 `supply bus not found, using dummy regulator` 这行是否消失,并实测插入USB存储设备能否正常识别(`ls /sys/bus/usb/devices/` 应能看到新增设备节点,`dmesg` 应能看到设备插入及usb-storage驱动绑定日志)

## 6. 补充参考信息

- 相关中文社区帖子(记录了该设备u-boot替换、TFTP救砖等刷机流程,内含"2026/06/09更新:重做DTS表,已解决识别问题和网口缺少还有USB问题"的说明,但从本次实测看USB供电问题仍未完全解决):
  `https://www.right.com.cn/forum/forum.php?mod=viewthread&tid=8475922`
- 固件来源仓库:`https://github.com/SamZong233/immortalwrt`,release tag `NetCore_N30_Pro_FW_V2`
- 官方ImmortalWrt该设备下载页(仅有官方原版,缺少lan口和usb问题未修复):
  `https://firmware-selector.immortalwrt.org/?version=25.12.0&target=mediatek%2Ffilogic&id=netis_nx30v2`

## 7. 期望的最终交付物

修复DTS中USB供电regulator配置后,重新编译生成的完整固件镜像,格式为可通过 `sysupgrade` 命令直接刷入的 `.itb` 文件(mediatek/filogic平台squashfs+UBI格式),需保持:
- 5个LAN口正确识别(当前已工作,请勿破坏)
- USB 2.0 与 USB 3.0 总线均能正常供电并识别外接USB设备(存储设备、CPE设备等)
