# elish-alarm

> **⚠️ 重要：本仓库文档由 AI 辅助生成。** 分区、刷写类命令一旦写错
> 可能造成数据丢失或设备变砖——**执行前逐条核对扇区号/分区名/槽位**,
> 不要整段照抄。备份先行。

[English](README_EN.md)

在小米平板5 Pro(**elish**，骁龙870 / SM8250-AC）上运行 Arch Linux ARM。

本仓库包含从原生 Android 到可启动的 Arch Linux ARM 系统所需的全部内容：

1. **UEFI 固件** —— 在 [luckyle7749/edk2-msm-elish](https://github.com/luckyle7749/edk2-msm-elish)
   单独构建和发布。将 `boot-elish.img` 刷入 `boot_b`,Android 保留在 `boot_a`。
2. **内核** —— postmarketOS SM8250 内核（`7.2.0-dev` 分支）+ 三个本地小补丁
   （见 [docs/kernel.md](docs/kernel.md))。预编译 `Image` 在 [esp/](esp/),
   配套内核模块在 [modules/](modules/)(**必装**,Wi-Fi/音频/触摸驱动都是模块)。
   ⚠️ `esp/simpleinit.uefi.cfg` 与本仓 `edk2/boot-elish.img` 配套使用；
   旧版 UEFI 固件可能无法解析，不要混用。
3. **厂商固件** —— 从工作机镜像提取，位于 [firmware/](firmware/),
   含 CS35L41 八扬声器音频调校。来源与版权说明见
   [firmware/README.md](firmware/README.md)。

## 目录结构

```
edk2/      预编译 UEFI 镜像 boot-elish.img(源码在 edk2-msm-elish 仓)
kernel/    .config + 针对 pmOS sm8250 内核的本地补丁
esp/       ESP 分区全部内容(Image、启动菜单、双面板 dtb、SwitchSlotsApp)
modules/   内核模块树(拷到 /lib/modules/7.2.0-elish-arm64;必装,
           Wi-Fi/音频/触摸驱动都在这)
firmware/  厂商 blob(DSP、音频功放、触摸、传感器注册表)
configs/   安装到目标机固定路径的文件
           (fstab+persist、ath11k MAC 修复、QCA6390 PCIe 重扫、iwd、UCM2 音频路由,
            传感器守护:hexagonrpcd/libssc/qbootctl 配置)
docs/      安装流程与各子系统文档
```

## 快速上手（概览）

```sh
# 1. UEFI —— 镜像在 edk2/,或见 edk2-msm-elish 的 Release;只刷 slot B
fastboot flash boot_b edk2/boot-elish.img && fastboot set_active b

# 2. 分区 + 在 linux 分区上安装 Arch Linux ARM rootfs,
#    ESP 文件(Image、dtb、simpleinit.uefi.cfg)放到 esp 分区
#    → docs/install.md

# 3. 启动进入系统后:安装厂商固件 + 部署内核到 ESP + 传感器/槽位守护
#    命令见 docs/install.md §4-5 与 §5.5
```

详细步骤:[docs/install.md](docs/install.md)

## 已测试配置

- **实测**:16GB 改装机 + CSOT 面板 —— Arch Linux ARM + KDE Wayland
- **已提供但未实测**:6GB/8GB 机型、BOE 面板
  （两种面板的 dtb 和触摸固件均已包含）
- Wi-Fi 需要附带的 `ath11k.link` MAC 修复（该芯片在 elish 上报告
  全零永久 MAC)，见 [docs/install.md](docs/install.md)
- 传感器（加速度计/光感 → 自动旋转、亮度）可用：hexagonrpcd 喂 SLPI
  注册表 + libssc 桥接到桌面（AUR 包），见
  [docs/install.md](docs/install.md) §5.5。不装这套守护时 SLPI 会
  每 ~40 秒崩溃重启一次（纯耗电），强烈建议安装

## 许可证

内核补丁与脚本遵循各自上游项目的许可条款。
`firmware/` 中的厂商固件 blob 版权归原厂商所有
(Qualcomm / Xiaomi / Cirrus / Novatek)，仅为设备启用而镜像分发 ——
详见 [firmware/README.md](firmware/README.md)。
