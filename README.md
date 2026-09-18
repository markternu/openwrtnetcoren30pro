# openwrtnetcoren30pro

**为磊科 Netcore N30 Pro(Netis NX30V2 / POWER30AX / GW3001 / GLC W7 同硬件)定制的 ImmortalWrt 固件工程**

联发科 MT7981B(Filogic 820)· 512MB RAM / 128MB SPI-NAND · 4×LAN + 1×WAN · USB 3.0

本仓库包含:**设备树/升级脚本补丁、内核模块与包配置、自检工具、刷机工具包、完整技术文档**,
以及通过 [Releases](../../releases) 分发的可直接刷写的 `.itb` 固件。

---

## 解决什么问题

上游/社区固件(NX30V2 模板)在这台机器上有四个真实痛点,本工程逐一修复并**实机验证**:

| # | 问题 | 根因 | 修复 |
|---|---|---|---|
| 1 | **USB 口完全不上电**(插任何设备都不亮、不枚举) | 设备树里 xHCI 节点没有 `vbus-supply`,内核只能用 dummy regulator;VBUS 由 **GPIO23** 门控却没人拉高 | DTS 增加 `regulator-usb-vbus`(GPIO23/高有效/5V/always-on)并挂到 `&xhci` |
| 2 | **LAN 口少一个** | 官方模板只描述了 3 个交换口 | 5 口全定义(`lan1~lan4` 物理口 + `lan5` 悬空 PHY 占位防崩) |
| 3 | 系统内 `sysupgrade` **提示成功但没生效** | 设备身份是 `netcore,n30pro`,而升级脚本白名单里只有 `netis,nx30v2` → 落到兜底分支把镜像写进 `kernel` 卷,而 u-boot 只从 `fit` 卷引导 | `platform.sh` 白名单补 `netcore,n30pro`,走 `fit_do_upgrade` |
| 4 | 装 openclash/passwall **依赖的 kmod 在所有仓库都找不到** | `kmod-tun`/`kmod-nft-tproxy`/`kmod-nft-socket`/`kmod-inet-diag`/`kmod-netlink-diag` 等符号默认 `DEFAULT:=m if ALL_KMODS` 不编译;且内核模块与自编译内核 ABI 绑定,仓库版本对不上 | 显式打开并编入固件(附离线 `.apk`) |

**实机验证结果**:USB 正常供电 → 中兴 F50 被识别为 USB 网卡 → 经 F50 正常上网;4 个 LAN + WAN 正常;
openclash/passwall 依赖内核模块齐备。

---

## 一键安装

> 仓库是**公开**的,不需要登录。脚本全部存在本仓库,用法与 ohmyzsh 官方一致:`sh -c "$(curl ...)"`。

### 🍓 树莓派(推荐:一条命令搞定全部)

刚烧好 Raspberry Pi OS、SSH 进去后的**第一条命令**:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install-pi.sh)"
sh -c "$(wget -qO-  https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install-pi.sh)"
# 国内更快(jsDelivr 镜像):
sh -c "$(curl -fsSL https://cdn.jsdelivr.net/gh/markternu/openwrtnetcoren30pro@main/install-pi.sh)"
```

它会**按顺序自动完成**(幂等,可重复运行):

| 顺序 | 内容 |
|---|---|
| 1️⃣ **第一个安装任务** | **oh-my-zsh**(装 zsh/git → 克隆 → 写 `.zshrc` → 换登录 shell;GitHub 失败自动切 Gitee) |
| 2️⃣ | 安装 **TFTP 服务**(`tftpd-hpa` + `tcpdump`,目录 `/srv/tftp`) |
| 3️⃣ | 从本仓库 **Releases 下载最新定制 OpenWrt 固件**,`sha256` 校验后放进 `/srv/tftp`(顺带下官方 u-boot FIP) |
| 4️⃣ | 下载**刷机工具包**到 `~/n30kit`(救砖网络 / 收尾 / 刷后自检 / 固件下载器) |
| 5️⃣ | 打印下一步:只需再跑 `sudo ~/n30kit/pi-net-on.sh` 就能按 Reset 刷机 |

常用参数:`--no-omz` / `--no-tftp` / `--no-firmware` / `--mirror` / `--version v1.0.0` /
`--base-url <镜像>` / `--without-uboot` / `--dry-run`(预演,不改动系统)。

### 路由器(刷完定制固件后)

> OpenWrt 固件默认只带 `uclient-fetch`(没有 curl/wget),所以额外给了零依赖版本。

#### 任务 1 · oh-my-zsh(第一件要做的事)

```sh
# OpenWrt 路由器(零依赖,推荐)
sh -c "$(uclient-fetch -O - https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install.sh)"

# 有 curl / wget 的系统(与 ohmyzsh 安装方式同款)
sh -c "$(curl -fsSL https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install.sh)"
sh -c "$(wget -qO-  https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main/install.sh)"
```

自动:装 `zsh`(+`git`/证书)→ 克隆 oh-my-zsh(GitHub 失败自动切 Gitee 镜像)→
写 `~/.zshrc`(原文件备份)→ 把登录 shell 换成 zsh。装完 `exec zsh` 进入。

```sh
... install.sh -- --mirror        # 国内走 Gitee 镜像
... install.sh -- --theme agnoster
... install.sh -- --uninstall     # 卸载并还原
... install.sh -- --dry-run       # 只预览,不改动
```

#### 任务 2 · 其他(常用工具 / 代理插件)

```sh
BASE=https://raw.githubusercontent.com/markternu/openwrtnetcoren30pro/main

# 路由器:常用工具 + 自动跑一次 USB 自检
sh -c "$(uclient-fetch -O - $BASE/install-extras.sh)"

# 路由器:OpenClash + PassWall(内核模块本项目固件已内置)
sh -c "$(uclient-fetch -O - $BASE/install-extras.sh)" -- --with-proxy

# 路由器:网页终端(浏览器操作,端口 7681)
sh -c "$(uclient-fetch -O - $BASE/install-extras.sh)" -- --with-ttyd

# (树莓派的对应需求已由上面的 install-pi.sh 一条命令覆盖)
```

> 💾 oh-my-zsh 约占 20–30MB,装前先 `df -h /overlay` 看剩余空间(不足 40MB 就别装)。

---

## 快速开始

> 🍼 **完全新手(从快递箱开始)请看** →
> [《喂饭教程:从零到上网(树莓派从零 + 路由器从原厂系统)》](docs/喂饭教程-从零到上网%28树莓派+原厂路由器%29.md)
> 里面有物料清单、树莓派烧卡、TFTP 搭建、原厂系统备份、换 u-boot、整刷、F50 上网的每一步与"应该看到什么"。

### 1. 下载固件

**在电脑上**:到 [Releases](../../releases) 下载下表资产。

**下载通道说明**(只有两条,且都来自本仓库,不依赖任何第三方镜像站):

| 通道 | 地址形态 | 说明 |
|---|---|---|
| ① GitHub 直链 | `github.com/<repo>/releases/download/<tag>/<file>` | Release 官方资产 |
| ② jsDelivr CDN | `cdn.jsdelivr.net/gh/<repo>@main/firmware/<file>` | jsDelivr 只是 CDN,**镜像的是本仓库 `firmware/` 目录里真实提交的文件**(所以仓库内保留了一份固件副本,约 27MB) |

`install-pi.sh` / `flash-kit/pi-fetch-firmware.sh` 会依次尝试这两条通道并**自动重试**,
下载完一律用 `SHA256SUMS` 校验;你也可以用 `--base-url` 指定自己的镜像。

**也可以在设备上直接下**(仓库公开,无需登录):

```sh
# 树莓派 / 路由器 / 任意 Linux:
BASE=https://github.com/markternu/openwrtnetcoren30pro/releases/latest/download
curl -fLO $BASE/immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb
curl -fLO $BASE/SHA256SUMS
grep netis_nx30v2 SHA256SUMS > check.txt && sha256sum -c check.txt && rm check.txt
```

> 树莓派上更省事的做法:`flash-kit/pi-fetch-firmware.sh --install` 会自动取最新版本、
> 下载、校验 sha256 并放进 `/srv/tftp`。

| 资产 | 用途 |
|---|---|
| `immortalwrt-mediatek-filogic-netis_nx30v2-squashfs-sysupgrade.itb` | **u-boot TFTP 整刷**(文件名与 u-boot `bootfile_fw` 一致) |
| `immortalwrt-mediatek-filogic-netcore_n30pro-squashfs-sysupgrade.itb` | 系统内 `sysupgrade` |
| `…-initramfs.itb` | 仅内存运行,不写 flash(试探用) |
| `kmods-apk-*.zip` | 本次新增 kmod 的离线 `.apk` |
| `SHA256SUMS` / `manifest` | 校验与包清单 |

### 2. 刷机(两条路,任选)

* **推荐:u-boot TFTP 整刷** —— 直接重建 `fit` 卷,绕开升级脚本。
  见 [`flash-kit/`](flash-kit/)(含树莓派 TFTP 一键脚本,已固化 nmcli 持久路由、`src` 绑定、`rp_filter` 三个实战坑)。
* **系统内**:`sysupgrade -F <…netcore_n30pro…itb>`(本工程已修好升级脚本)。

> ⚠️ 刷机有风险,请先备份分区(`mtd5_ubi.bin` 等)。固件只写 `ubi` 分区,不触碰 BL2/FIP,
> 配合 u-boot TFTP 恢复模式可随时回退。

### 3. 刷完自检

```sh
grep DISTRIB_REVISION /etc/openwrt_release   # 应为 r37877-n30pro
usb-fix-check                               # 一键自检(USB 供电/驱动/设备树/包)
sh flash-kit/verify-after-boot.sh           # 或跑这个
```

安装代理应用(依赖已内置,不再报"未提供"):

```sh
apk update
apk add luci-app-openclash
# 或
apk add luci-app-passwall luci-i18n-passwall-zh-cn
```

---

## 仓库结构

```
install-pi.sh         🍓 树莓派一站式一键安装(oh-my-zsh + TFTP + 固件 + 工具包)
install.sh            一键安装:oh-my-zsh(路由器刷完新系统的第一个任务)
install-extras.sh     一键安装:其他(常用工具/代理插件/树莓派刷机环境)
docs/          技术报告、根因分析、刷机教程、实战复盘、复现编译说明
patches/       设备树 / 升级脚本 / 包列表 / 编译期修补(附说明)
packages/      本地 OpenWrt 包:usbfix(/usr/sbin/usb-fix-check 自检)
flash-kit/     树莓派 TFTP 刷机工具包(脚本 + 步骤 + 排错表)
scripts/       apply-patches.sh / build.sh(一键复现编译)
firmware/      固件副本(供 jsDelivr CDN 镜像,内容与 Release 一致)
release/       最新固件的 SHA256SUMS 与包清单
appendix/      开发过程原始记录(非正式文档)
```

### 建议阅读顺序

0. [**`docs/喂饭教程-从零到上网(树莓派+原厂路由器).md`**](docs/喂饭教程-从零到上网%28树莓派+原厂路由器%29.md) — 🍼 零基础照着抄
1. [`docs/01-问题定位-USB供电缺失技术报告.md`](docs/01-问题定位-USB供电缺失技术报告.md) — 问题从哪来
2. [`docs/04-第二轮-根因修复说明(sysupgrade写错卷).md`](docs/04-第二轮-根因修复说明%28sysupgrade写错卷%29.md) — 最反直觉的那个坑
3. [`docs/刷机实战-第三轮全过程(树莓派TFTP).md`](docs/刷机实战-第三轮全过程%28树莓派TFTP%29.md) — 实战步骤与三个网络陷阱
4. [`docs/复现编译说明.md`](docs/复现编译说明.md) — 自己编一份

---

## 从源码复现编译

```sh
git clone https://github.com/SamZong233/immortalwrt.git
git -C immortalwrt checkout 3c71dfc2b67dc7808d110afa66d66527f4b2ce2e
./scripts/build.sh immortalwrt $(nproc)
```

需要在 Linux(或 macOS 上的 Linux 虚拟机)与**大小写敏感**文件系统上构建。
`build.sh` 已固化全部坑点:feeds 最小化、默认不选的内核模块强制开启、apk 版本号修补、
避免编译 host LLVM、避开 `bpf-headers`、内核配置变化后清理旧 ABI 的 kmod 等。
细节见 [`docs/复现编译说明.md`](docs/复现编译说明.md)。

---

## 版本说明

| 版本 | 内容 |
|---|---|
| **v1.0.0**(当前) | 首个正式版本:USB VBUS 供电修复 + 中兴 F50 USB 上网 + 4LAN/WAN 映射 + `sysupgrade` 根因修复 + openclash/passwall 内核模块 + 内置 LuCI 中文 + `usbfix` 自检 |

> 本固件基于 ImmortalWrt 25.12-SNAPSHOT(`r37877-n30pro`),内核 `6.12.91`。
> 早期内部迭代版本(未发布、存在刷机不生效问题)请勿使用。

---

## 来源与致谢

* [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) / [OpenWrt](https://openwrt.org) — 构建系统与内核
* [SamZong233/immortalwrt](https://github.com/SamZong233/immortalwrt) commit `3c71dfc2b6` — 源码基线
* netis NX32U 官方设备树 — GPIO23 作 USB VBUS 的参考依据
* 社区(bfdeh / 54iter 等)关于 N30 Pro USB 与端口的公开记录 — 交叉验证

## 许可

本项目以 **GPL-2.0** 发布(与 OpenWrt/ImmortalWrt 一致),见 [LICENSE](LICENSE)。
固件内含第三方组件,版权归各自作者所有。
