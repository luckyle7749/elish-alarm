# Kernel: 7.2.0-elish-arm64

[中文](kernel.md)

## Source

- **Repository**: <https://gitlab.postmarketos.org/soc/qualcomm-sm8250/linux>
- **Branch**: `7.2.0-dev`
- **Baseline commit**: `3c5440e9dd3c3e3b5735ad8f1b22bdfd02c707d9`
  (tip of 7.2.0-dev at pull time; verified file-identical to the built tree)
- **Local build version**: `7.2.0-elish-arm64`

**Thanks to the postmarketOS SM8250 kernel maintainers** — this kernel
rests entirely on their ongoing SM8250/elish enablement. Recent major
contributors include Jianhua Lu, Xin Xu, Dawid Wróbel and other
community contributors.

## Local changes (`kernel/patches/`)

Only 3 small changes on top of the upstream baseline, all in the **audio
subsystem**, exported as `kernel/patches/*.patch`:

| Patch | Change | Why |
|---|---|---|
| `0001` | `sound/soc/qcom/qdsp6/q6asm-dai.c`: restrict playback to S16 | The DSP path outputs abnormal volume/distortion at non-S16 sample formats; S16 lock is the tested-stable combination |
| `0002` | `sound/soc/qcom/sm8250.c`: set codec RX channel map for the 8× CS35L41 | elish has 8 amps (4 top + 4 bottom); without the map L/R channels are wrong. B group (bus1)=right, T group (bus3)=left |
| `0003` | `sound/soc/codecs/cs35l41-lib.c`: skip PUP_DONE wait on INT_BOOST, demote PDN timeout to warning | The chip never reports the completion bit on this path; the wait times out and fails the whole DAPM power event, leaving amps unpowered. As a warning all 8 work |

Apply:

```bash
git clone https://gitlab.postmarketos.org/soc/qualcomm-sm8250/linux.git
cd linux && git checkout 3c5440e9dd3c3e3b5735ad8f1b22bdfd02c707d9
git am <this repo>/kernel/patches/*.patch
make ARCH=arm64 LLVM=1 Image modules
```

Toolchain: Clang 23.1.4 + LLD (the `.config` is a Clang build,
`CONFIG_LTO_NONE`).

## Added firmware

Beyond the kernel, the device needs these firmware files (**not kernel
source**, not shipped as patches — mirrored under `firmware/`):

| File | Location | Source / notes |
|---|---|---|
| `cs35l41-dsp1-spk-prot.wmfw` | `/lib/firmware/cirrus/` | Xiaomi-custom CS35L41 DSP firmware v0.33.0, matches factory tuning |
| `cs35l41-dsp1-spk-prot-{tlh,tll,trh,trl,blh,bll,brh,brl}.bin` | `/lib/firmware/cirrus/` | **Position-specific tuning binaries** for all 8 amps; must pair with v0.33.0 — upstream v0.65.0 firmware is unusable (coefficient version mismatch, wants 29.85.0) |
| `qcom/sm8250/xiaomi/elish/{adsp,cdsp,slpi,venus,a650_zap}.mbn(+splits)` | `/lib/firmware/qcom/` | Processor firmware extracted from the device vendor/persist partitions (DSP/sensors/video decode) |
| `qcom/a650_{gmu.bin,sqe.fw}` | `/lib/firmware/qcom/` | Adreno 650 GPU firmware (from the `linux-firmware` package) |
| `novatek/nt36523-{csot,boe}.bin` | `/lib/firmware/novatek/` | Touchscreen firmware, one per panel variant |
| Android `persist/audio/cs35l41_cal_spk*.bin` | device persist partition | Factory speaker calibration data (4 bytes/amp), reference only |

See `firmware/README.md` for the full list and provenance.
