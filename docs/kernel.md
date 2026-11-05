# 内核说明：7.2.0-elish-arm64

## 内核来源

- **仓库**: <https://gitlab.postmarketos.org/soc/qualcomm-sm8250/linux>
- **分支**: `7.2.0-dev`
- **基线提交**: `3c5440e9dd3c3e3b5735ad8f1b22bdfd02c707d9`
  (7.2.0-dev 当时的 tip;已验证与本机编译源码树逐文件一致）
- **本机编译版本**: `7.2.0-elish-arm64`

**感谢 postmarketOS SM8250 内核维护者们**——本设备的内核完全建立在他们对 SM8250/elish 平台的持续适配工作上。近期主要贡献者包括：Jianhua Lu、Xin Xu、Dawid Wróbel 以及社区各位提交者。

## 本人做的修改（kernel/patches/）

在上游基线之上仅有 3 处小改动，均为**音频子系统修复**，对应 `kernel/patches/` 下的 patch 文件：

| 补丁 | 改动 | 为什么 |
|---|---|---|
| `0001` | `sound/soc/qcom/qdsp6/q6asm-dai.c`：播放通路限制为 S16 | DSP 通路在非 S16 采样格式下会输出异常音量/失真；锁 S16 是实测稳定的组合 |
| `0002` | `sound/soc/qcom/sm8250.c`：为 8 路 CS35L41 设置 codec RX 声道映射 | elish 有 8 颗功放（顶4+底4），不修正映射时左右声道会错；现 B 组(bus1)=右声道，T 组(bus3)=左声道 |
| `0003` | `sound/soc/codecs/cs35l41-lib.c`：INT_BOOST 下跳过 PUP_DONE 等待，PDN 超时仅告警 | 该芯片此路径上不回报完成位，等待超时会让 DAPM 电源事件整体失败、功放上不了电；降级为告警后 8 路全部正常 |

应用方式：

```bash
git clone https://gitlab.postmarketos.org/soc/qualcomm-sm8250/linux.git
cd linux && git checkout 3c5440e9dd3c3e3b5735ad8f1b22bdfd02c707d9
git am <本仓库>/kernel/patches/*.patch
make ARCH=arm64 LLVM=1 Image modules
```

构建工具链：Clang 23.1.4 + LLD（内核 `.config` 为 Clang 构建，`CONFIG_LTO_NONE`）。

## 增加的固件

内核之外，设备运行还需要以下固件文件（**不属于内核源码**，未随补丁分发）：

| 文件 | 位置 | 来源/说明 |
|---|---|---|
| `cs35l41-dsp1-spk-prot.wmfw` | `/lib/firmware/cirrus/` | Xiaomi 定制 CS35L41 DSP 固件 v0.33.0，匹配出厂调校（来自 [armbian/firmware](https://github.com/armbian/firmware)） |
| `cs35l41-dsp1-spk-prot-{tlh,tll,trh,trl,blh,bll,brh,brl}.bin` | `/lib/firmware/cirrus/` | 8 颗功放的**位置专属调校二进制**，必须与 v0.33.0 配套；上游 v0.65.0 固件因系数版本不符（要 29.85.0）无法使用 |
| `qcom/sm8250/xiaomi/elish/{adsp,cdsp,slpi,venus,a650_zap}.mbn(+分片)` | `/lib/firmware/qcom/` | 从设备 `modem`/厂商分区提取的处理器固件（DSP/传感器/视频解码） |
| `qcom/a650_{gmu.bin,sqe.fw}` | `/lib/firmware/qcom/` | Adreno 650 GPU 固件 |
| `novatek/nt36523-csot.bin` | `/lib/firmware/novatek/` | 触摸屏固件 |
| Android `persist/audio/cs35l41_cal_spk*.bin` | 设备 persist 分区 | 出厂扬声器校准数据（4 字节/颗），供参考 |

详见 `firmware/README.md` 的完整清单与获取方式。
