# 安装:原生 Android → Arch Linux ARM

实测路径:16GB 改装机 + CSOT 面板,Android 保留在 slot A,Linux 从 slot B 启动。
全程不需要拆机、不需要 SD 卡(elish 也没有卡槽),工具只需要一台 PC + USB-C 线。

## 0. 前置:解锁 + 备份

```text
PC 工具         → adb + fastboot(Arch 上 pacman -S android-tools)
解锁 bootloader   → 官方 Mi Unlock(首次解锁有等待期)
进入 fastboot    → 关机后 音量- + 电源;或 adb reboot bootloader
```

**先备份再动手。** 当时的做法:进 Recovery(见 §1)后用 ADB root shell 把
全部分区 dd 出来 + GPT 头尾单独留档:

```sh
# recovery shell(root),对每个分区:
dd if=/dev/block/sdaN of=/sdcard/bkparts/<name>.img
# GPT 头尾两份都留(尾部是备份表,丢了照样翻车):
dd if=/dev/block/sda of=gpt-head.bin bs=512 count=34
sgdisk -b /sdcard/bkparts/gpt-full.bin /dev/block/sda   # 一份含头尾
persist.img 单独再备一份(校准数据,丢了 Wi-Fi MAC/传感器校准全没)
```

备份存到设备外(adb pull)。**没有 persist 备份不要继续。**

## 1. 分区(在 Recovery 里做)

出厂机全盘是 Android 分区,办法是**缩小 userdata,在尾部追加两个分区**——
不碰任何 Android 系统分区,代价只是 userdata 重建(data 会被清,MIUI 数据提前另备)。

需要一个能 `adb shell` 拿 root 的环境。当时用的
[web1n 的非官方 LineageOS(elish)](https://xdaforums.com/t/rom-unofficial-a16-elish-lineageos-23-2-for-xiaomi-pad-5-pro-wifi.4764518/)——
elish 是 A/B 分区、recovery ramdisk 在 `boot.img` 里，按其发布说明
`fastboot flash` 后进 recovery 即可（**注意：elish 的 bootloader 拒绝
`fastboot boot` 临时引导，只能 flash**)。**任何能给 root
shell 且带 sgdisk/mkfs 的环境都可以**(已 root 的 Android 也行)。

```sh
adb shell
# 先确认编号,别猜:
ls -l /dev/block/by-name/ | grep userdata     # → sda34
sgdisk -p /dev/block/sda                      # 看现状
```

```sh
# 第一步:读出 34 的实际起始扇区(-p 输出里 Number/Start/End 列)
sgdisk -p /dev/block/sda
# 假设 34 的 Start=22589440(你的机器不一样,抄你自己的数字)
# 缩 userdata 到 200G:200G = 200*1024*1024*1024/512 = 419430400 扇区,
# 新 End = Start + 419430400 - 1。示例:Start=22589440 → End=442019839
sgdisk -d 34 -n 34:22589440:442019839 -c 34:userdata /dev/block/sda
# 第二步:尾部追加(自动用最小可用起点)
sgdisk -n 0:0:+1G -c 0:esp   -t 0:EF00 /dev/block/sda   # → sda35
sgdisk -n 0:0:0    -c 0:linux -t 0:8300 /dev/block/sda  # → sda36,吃掉剩余
mkfs.vfat -F32 /dev/block/sda35
mkfs.ext4      /dev/block/sda36
```

> PARTLABEL 必须是 `esp` 和 `linux`(fstab 和内核 cmdline 按它认盘)。
> 改完回 Android 会要求 Format Data,属预期。

**Recovery 里缺工具怎么办**(第三方 recovery 的 toybox 经常没有
`sgdisk`/`mkfs.vfat`):

- 没有 sgdisk → 在 PC 上下载一个 **aarch64 静态 sgdisk**(发行版包或
  预编译静态版）,`adb push` 到 `/tmp`,`chmod +x` 后跑
- 没有 mkfs.vfat → 在 PC 上用 `mkfs.vfat`/`mtools` 先做一个 1G ESP 镜像，
  `adb push` 后 `dd of=/dev/block/sda35`
- 没有 mkfs.ext4 → 同理，PC 上 `mkfs.ext4` 做镜像再 dd；或先进 Linux
  再补（但 ext4 必须先建好，rootfs 要往里写）

最终布局(本机实测):

| PARTLABEL | 分区 | 大小 | 文件系统 | 作用 |
|---|---|---|---|---|
| userdata | sda34 | ~200G | f2fs | Android 数据(已缩小) |
| `esp` | sda35 | 1G | FAT32 | 挂 `/boot`,放 Image/dtb/菜单 |
| `linux` | sda36 | 剩余 | ext4 | Arch rootfs |

## 2. Rootfs(Recovery 里 push + 就地解包)

PC 下载 [ALARM aarch64 通用 rootfs](https://archlinuxarm.org/platforms/armv8/generic)
(`ArchLinuxARM-aarch64-latest.tar.gz`),然后:

```sh
# recovery shell:
mount /dev/block/sda36 /tmp/mnt
adb push ArchLinuxARM-aarch64-latest.tar.gz /tmp/mnt/rootfs.tar.gz
tar -xpf /tmp/mnt/rootfs.tar.gz -C /tmp/mnt && rm /tmp/mnt/rootfs.tar.gz
mount /dev/block/sda35 /tmp/mnt/boot   # ESP 挂到 rootfs 的 /boot
```

## 3. 部署仓库文件

分两段。**ESP 文件和 fstab 必须在 Recovery 里就放好**——SimpleInit 按
`@esp:/Image` 读内核,ESP 是空的首启必失败。§2 已把 sda36→`/tmp/mnt`、
sda35→`/tmp/mnt/boot` 挂好。把仓库 push 到 rootfs(如
`adb push elish-alarm /tmp/mnt/root/`),**cd 到仓库目录**后在 recovery
shell 里执行(无 sudo):

```sh
cp esp/* /tmp/mnt/boot/                 # ESP 全量:Image+菜单+双dtb+SwitchSlotsApp
cp configs/etc/fstab /tmp/mnt/etc/fstab # PARTLABEL 挂载,无需改 UUID
```

**其余等首次进 Linux 后做**(有 sudo、depmod 能跑、路径即真实路径),
仓库 clone/拷贝到 rootfs 后执行:

```sh
sudo mkdir -p /lib/modules/7.2.0-elish-arm64
sudo cp -a modules/. /lib/modules/7.2.0-elish-arm64/  # 内核模块,与 esp/Image 同一编译
sudo depmod -a
```

> 复查 ESP 内容:`sudo mount /boot`(fstab 生效的话已自动挂上)
> 再 `sudo cp esp/* /boot/` 补齐。
> 如果你坚持在 Recovery 里完成剩下的步骤:所有目标路径加 rootfs 前缀
> (`/etc`→`/tmp/mnt/etc`、`/lib/modules`→`/tmp/mnt/usr/lib/modules`),
> `depmod` 留到进系统再跑——原样照抄会写进 recovery 自己的 tmpfs,
> 重启就没了。

没 clone、只有 Release 附件的：模块树等价于
`sudo tar -xJf modules-7.2.0-elish-arm64.tar.xz -C /usr/lib/modules/`
（注意是 `/usr/lib/modules`,**不是 `-C /`**——tar 顶层就是版本名目录）。

> 仍想在 recovery 里做的话：目标要加上 rootfs 前缀——`/boot`→
> `/tmp/mnt/boot`、`/etc`→`/tmp/mnt/etc`、`/lib/modules`→
> `/tmp/mnt/usr/lib/modules`,去掉 `sudo`,且 `depmod` 留到首启后跑。
> 直接照抄下面命令会把文件写进 recovery 自己的 tmpfs，重启全没。

> `Image` 只负责点亮——**Wi-Fi/声卡/触摸的驱动都在 `modules/` 里**(编译为 =m),
> 不装会得到一台"能启动没功能"的机器。

按你的面板改 `esp/simpleinit.uefi.cfg` 的 `dtb` 行(`elish-csot.dtb` ↔ `elish-boe.dtb`)。

## 4. 固件 + 音频

```sh
sudo install -Dm644 firmware/sm8250/* -t /usr/lib/firmware/qcom/sm8250/xiaomi/elish/
sudo install -Dm644 firmware/qcom/*    -t /usr/lib/firmware/qcom/
sudo install -Dm644 firmware/cirrus/*  -t /usr/lib/firmware/cirrus/
sudo install -Dm644 firmware/novatek/* -t /usr/lib/firmware/novatek/
sudo cp -a firmware/hexagonfs/. /usr/share/qcom/sm8250/Xiaomi/elish/
```

音频三要素:

- `firmware/sm8250/adsp*` + `firmware/cirrus/cs35l41*` —— DSP 与功放固件
- UCM2 路由(**连同 conf.d 链接一起**,否则声卡匹配不到配置):
  ```sh
  sudo cp -r configs/usr/share/alsa/ucm2/Xiaomi/elish /usr/share/alsa/ucm2/Xiaomi/
  sudo cp -a configs/usr/share/alsa/ucm2/conf.d /usr/share/alsa/ucm2/
  ```
- `kernel/patches/` 三个补丁是**正确放音的必要条件**
  (S16 位深限制、左右声道映射、PUP 超时降级)——自己构建内核时必须打上

## 5. Wi-Fi(硬件怪癖 ×3)

```sh
sudo cp configs/etc/systemd/network/10-ath11k.link /etc/systemd/network/
sudo cp configs/etc/systemd/system/pcie-rescan.service /etc/systemd/system/
sudo cp -r configs/etc/systemd/system/iwd.service.d /etc/systemd/system/
sudo systemctl enable iwd pcie-rescan
```

| 文件 | 解决的坑 |
|---|---|
| `10-ath11k.link` | ath11k 报全零永久 MAC;仓库默认 `MACAddressPolicy=persistent` 按 machine-id 生成唯一稳定地址 |
| `pcie-rescan.service` | QCA6390 PCIe 链路训练偶发失败,wlan0 干脆不出现 → 开机最多重扫 10 次兜底 |
| `iwd` drop-in | iwd 抢在 udev 写完 MAC 前拉起接口 → 让它等 wlan0 就绪 |

**MAC 两种写法**:

- 仓库默认 `MACAddressPolicy=persistent`——每机唯一、零配置;**未实机验证**（原理上与驱动无关，应可行）
- 实测设备用的是**固定出厂 MAC**（安卓真实 MAC，已验证）：用 `10-ath11k.factory-mac.link.example` 模板——填入你的出厂 MAC 后改名为 `10-ath11k.link` 替换默认文件。出厂 MAC 在 `persist` 分区的 `wlan/wlan_mac.bin` 里（格式 `wlan0=AABBCCDDEEFF`)

**首启即联网**:进系统前把凭据写进 rootfs,iwd 起来自动连:

```ini
# /var/lib/iwd/<你的SSID>.psk
[Security]
Passphrase=你的WiFi密码
```

iwd 不在 ALARM base 里——没有网就装不了它。两条路：

- **预装（推荐）**:PC 从 ALARM 镜像站下载 `iwd` 和依赖 `ell` 的
  aarch64 包，连同凭据放进 rootfs，进系统后：
  ```sh
  sudo pacman -U /tmp/ell-*.pkg.tar.zst /tmp/iwd-*.pkg.tar.zst
  sudo systemctl enable --now iwd
  ```
- **救场**：首启用 USB-C 以太网卡/手机 USB 网络共享联网，再正常
  `pacman -S iwd`

ALARM 默认账户 `alarm:alarm`,`root:root`(sshd 随 base 启用，能直接
ssh 进去——前提是 wlan0 已上线）。

**蓝牙（QCA6390 出厂无地址）**：芯片上电后 `hci0` 携带全零 BDADDR
注册，内核把它标成"未配置"——`bluetoothctl` 里**根本看不到控制器**
（现象：`No default controller available`，但 dmesg 固件下载成功）。
修法是把出厂地址写进去。仓库提供脚本+service:

```sh
sudo install -Dm755 configs/usr/local/bin/elish-btaddr.sh -t /usr/local/bin/
sudo cp configs/etc/systemd/system/elish-btaddr.service /etc/systemd/system/
sudo systemctl enable --now elish-btaddr.service
```

默认动态模式：脚本从 `persist` 的 `bluetooth/.bt_nv.bin`(6 字节
裸二进制，= Wi-Fi MAC+1）读出本机出厂地址写入——任何机器零配置。
想写死：用 `elish-btaddr.service.d/override.conf.example` 模板——
填入出厂 BT MAC 后去掉 `.example` 后缀（即 `override.conf`,
等价于 `systemctl edit elish-btaddr` 写入）:

```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/elish-btaddr.sh 你的出厂BT_MAC
```

验证：`bluetoothctl show` 应列出 `elish` 控制器且 `Powered: yes`,
`bluetoothctl scan on` 能扫到周边设备。

## 5.5 传感器 + A/B 槽位（可选项，强烈建议）

elish 的加速度计/陀螺仪/光感/磁力计由 SLPI（传感器协处理器）托管，
缺少用户态守护进程时 SLPI 会**每约 40 秒崩溃重启一次**（内核日志
`crash detected in slpi`)。补链：AUR 装 `hexagonrpcd`（喂 hexagonfs
注册表给 DSP)+ `qbootctl`（槽位标记）+ `libssc`（传感器到用户态的桥，
官方仓库即 `libssc`，或 AUR `libssc-git`)。三个包都在 AUR——新装的
ALARM 没有 AUR helper，先 `sudo pacman -S --needed base-devel git` 再
按 AUR 标准流程 `makepkg -si` 构建（或装 yay):

```sh
yay -S hexagonrpcd qbootctl libssc-git

sudo cp configs/etc/conf.d/hexagonrpcd-sdsp /etc/conf.d/
sudo cp configs/etc/udev/rules.d/61-libssc.rules /etc/udev/rules.d/
sudo cp configs/etc/systemd/system/qbootctl.service /etc/systemd/system/
sudo cp -r configs/etc/systemd/system/hexagonrpcd-sdsp.service.d /etc/systemd/system/
sudo cp -r configs/etc/systemd/system/iio-sensor-proxy.service.d /etc/systemd/system/

sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=misc
sudo systemctl enable --now hexagonrpcd-sdsp qbootctl iio-sensor-proxy
```

| 文件 | 作用 |
|---|---|
| `/etc/conf.d/hexagonrpcd-sdsp` | 告诉 daemon hexagonfs 注册表在哪；**service 缺它会直接起不来** |
| `61-libssc.rules` | 给 fastrpc 设备打 `IIO_SENSOR_PROXY_TYPE` 标签(iio-sensor-proxy 的 accel 驱动靠它认领设备)+ `ACCEL_MOUNT_MATRIX` 挂载矩阵 |
| `qbootctl.service` | 每次开机把当前槽位标 successful——不标的话启动计数扣完，bootloader 会**自动切回 Android 槽位** |
| fstab `persist` 行 | SLPI 要读写 `/mnt/vendor/persist/sensors` 校准数据；没挂载 = 崩溃循环复发 |
| `hexagonrpcd-sdsp` drop-in `restart.conf` | `Restart=always`——daemon 会偶发**干净退出**(status 0，运行数十分钟后),systemd 视其为"完成"不再拉起，随后 SLPI 看门狗崩溃循环、传感器静默全灭(报错都指向别处，极难排查)。必须让它死必复活 |
| `hexagonrpcd-sdsp` drop-in `persist-perms.conf` | **安卓每次启动都会把注册表属主重置回安卓用户**,daemon(fastrpc 组）随即写不进去。此 drop-in 在 daemon 每次启动前以 root 自动 `chgrp fastrpc + g+rw`——双系统来回切也免疫 |
| `75-elish-ignore-tablet-mode.rules`(plasma-mobile 才装） | pogo 键盘主控（`3206:3ffc`）常驻枚举鼠标/触摸板,KWin 据此判"非平板"→自动旋转永不激活。打 `kwin-ignore-tablet-mode` tag 让它退出判定 |
| `49-sensor-proxy-claim.rules`(plasma-mobile 才装） | polkit 默认只放行座位活动会话的 sensor claim；登录早期 claim 必撞 greeter 未退场窗口被拒。无条件放行，防旋转/旋转按钮随机消失 |
| `iio-sensor-proxy` drop-in | 保险丝:传感器栈异常时(如 persist 未挂载、守护未起)代理会停不下来,把关机等待从默认 90s 压到 10s;栈正常时它不参与任何功能 |

挂载后**还要修一次权限**——persist 里的传感器注册表属主是安卓
system(uid 1000，本机显示为普通用户）,daemon 以 `fastrpc` 组运行
写不进去（日志刷 `Tried to open … temp.json`):

```sh
sudo chgrp -R fastrpc /mnt/vendor/persist/sensors/registry
sudo chmod -R g+rw /mnt/vendor/persist/sensors/registry
sudo find /mnt/vendor/persist/sensors/registry -type d -exec chmod g+s {} +
```

（只动组不动属主，安卓侧不受影响；setgid 让后续新文件继承 fastrpc 组。
此后每次 Arch 启动由 `persist-perms.conf` drop-in 自动纠偏——**安卓
每启一次就重置一次属主**，手动修只能管当次启动）

⚠️ 挂载矩阵**已实测标定**：仓库用 `"-1, 0, 0; 0, -1, 0; 0, 0, 1"`
(X/Y 取反、Z 不变）——postmarketOS 的三轴全取反矩阵在这台机器上
平躺会判成 face-down，实测不可用。验证：`sudo monitor-sensor`,
竖屏口朝下应报 `normal`、横屏口朝右报 `right-up`、平躺屏朝上 `face-up`。

**KDE 桌面自动旋转**:Plasma 只在"触控模式"下消费方向数据——
设置 → 工作区行为 → 常规行为 → **触控模式选"总是启用"**;
显示器配置里 autoRotation 保持 `InTabletMode` 即可（等效于恒平板）。

**iio-sensor-proxy 上游竞态 bug(必须打补丁,否则旋转大概率失灵)。**
3.9 版里 proxy 先注册 D-Bus 对象、后枚举传感器(SSC 枚举约 1 秒,
每颗传感器一轮 QMI 对话)。KDE 在 D-Bus 名字出现瞬间 claim
accelerometer——每次都抢在枚举完成前：claim 被记入客户端表并返回
成功，但此时设备尚未绑定，polling 从不启动；随后冷插拔绑定路径
**不检查客户端表、不补 polling**(热插拔路径会，冷插拔漏了)，
表现为 `Has accelerometer` 但 orientation/tilt 恒 `undefined`。
仓库含补丁 `patches/iio-sensor-proxy/0001-poll-sensors-claimed-during-enumeration.patch`
(枚举完成后补查客户端表并启动 polling)，应用方法:

```sh
git clone --depth 1 -b 3.9 https://gitlab.freedesktop.org/hadess/iio-sensor-proxy.git
cd iio-sensor-proxy
patch -p1 < /path/to/0001-poll-sensors-claimed-during-enumeration.patch
meson setup build -Dssc-support=enabled   # auto 模式不会编译 SSC 驱动
ninja -C build
sudo systemctl stop iio-sensor-proxy
sudo cp build/src/iio-sensor-proxy /usr/lib/iio-sensor-proxy
sudo systemctl start iio-sensor-proxy
```

补丁是被覆盖的二进制，**pacman 升级会还原它**——冻结此包直到上游
合并（补丁方向与热插拔路径已有逻辑一致，适合提 MR):

```sh
# /etc/pacman.conf
IgnorePkg = iio-sensor-proxy
```

验证修复生效：`journalctl -u iio-sensor-proxy` 里应出现
`claimed during enumeration, starting polling` 与
`Enabling sensor ... continuous`。

**排障：accel 有设备但无数据的其他原因。** `monitor-sensor` 显示
`Has accelerometer` 但 orientation/tilt 恒为 `undefined`（而 `ssccli`
有数），除上述竞态外还可能是 QMI 订阅僵死——proxy 被 SIGKILL 后 SLPI
侧残留死订阅，enable 请求得不到应答。**别 SIGKILL**:
`sudo systemctl restart hexagonrpcd-sdsp iio-sensor-proxy`（重启 daemon
让 DSP 感知断链），不行就重启整机。仓库的 proxy drop-in 已加
`After=/Wants=hexagonrpcd-sdsp` 保证启动顺序。
诊断时可给 proxy 开调试日志：`systemctl edit iio-sensor-proxy`
写入 `[Service]` 段加 `Environment=G_MESSAGES_DEBUG=all`。

⚠️ **休眠(suspend)目前不可用**:s2idle 唤醒后 QMI/传感器订阅状态
不可恢复——SLPI 崩溃循环复发，且重启 daemon/proxy、重置 remoteproc
均无法救回，只能整机重启。建议直接屏蔽，只用熄屏：

```sh
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Plasma Mobile 自动旋转（可选桌面会话）

`pacman -S plasma-mobile` 后登录器会多出 Plasma Mobile 会话（与桌面 Plasma
共存，布局互不影响）。移动端旋转全靠 KWin 的平板判定，本机有两个硬件怪癖
必须修，否则旋转必死：

**pogo 键盘主控冒充鼠标（必修）。** 键盘触点的 USB 主控芯片
（Xiaomi `3206:3ffc`）无论插不插键盘都常驻枚举 keyboard+mouse+touchpad
三个 HID 接口。KWin 判定 `isTablet = 有触摸 && 无指针设备`——这颗假指针
让判定永远为"笔记本"，平板模式永不激活，自动旋转整个链路不启动。安装
`configs/etc/udev/rules.d/75-elish-ignore-tablet-mode.rules` 给该 VID:PID
打 `kwin-ignore-tablet-mode` tag（KWin 官方预留的忽略标记），然后
`udevadm control --reload` 并重新登录。生效后
`busctl --user get-property org.kde.KWin /org/kde/KWin
org.kde.KWin.TabletModeManager tabletMode` 应为 `true`。

**polkit 早期 claim 被拒（保险丝）。** KWin/移动 shell 在会话激活前就可能
`ClaimAccelerometer`，而 polkit 默认只放行"座位上的活动会话"——greeter
会话还没退场时 claim 一律 `AccessDenied` 且客户端不重试，症状随机（旋转
或控制中心的旋转按钮任一消失）。安装
`configs/etc/polkit-1/rules.d/49-sensor-proxy-claim.rules` 对该 action
无条件放行（claim 只是开传感器，无安全影响）。

**别踩的配置坑：**

- `kwinrc [Input] TabletMode=on` **无效**——KWin 用 `readPathEntry` 读该键，
  相对路径会被展开成 `$HOME/on`，永远匹配不上 `"on"`（疑似上游 bug）。
  有 udev tag 后 `auto`（按需启用）本身就工作，不需要强制 On。
- 直接编辑 `kwinoutputconfig.json` 里的 `autoRotation` 会被 KWin 内存态
  覆写，想改策略只能走系统设置→显示 里的"自动旋转"下拉。

## 6. 刷入 UEFI,首启

镜像在仓库 `edk2/boot-elish.img`（或从
<https://github.com/luckyle7749/edk2-msm-elish> 自行构建)。
一个镜像覆盖全部 elish 内存版本（6GB / 8GB / 16GB 改装）。刷到 **slot B**,
Android 在 slot A 不动：

```sh
fastboot getvar product        # 必须是: elish
fastboot flash boot_b edk2/boot-elish.img
fastboot set_active b
fastboot reboot
```

进入 SimpleInit 菜单（10 秒超时，默认启动 Arch)。首启可用 USB-C 键盘
（驱动内建）或预写的 iwd 凭据直接 ssh 进去。

## 7. 切回 Android

- SimpleInit 菜单"Reboot to Android (switch to slot A)"→ 调 ESP 上的
  `SwitchSlotsApp.efi`
- 或 fastboot:`fastboot set_active a`
