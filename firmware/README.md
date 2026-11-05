# Firmware blobs

Vendor binaries mirrored from a working elish unit. **These files are
proprietary** — copyright belongs to Qualcomm / Xiaomi / Cirrus Logic /
Novatek. They are redistributed here solely to enable Linux on this device,
the same role as `lujianhua/xiaomi-elish-firmware` (used by postmarketOS
`firmware-xiaomi-elish`) and similar device-firmware repositories.

## Contents and provenance

| Directory | Files | Installs to | Source |
|---|---|---|---|
| `sm8250/` | `adsp.*`, `cdsp.*`, `slpi.*`, `venus.*` (`.mbn` + `.bXX` + `.jsn`), `a650_zap.mbn` | `/usr/lib/firmware/qcom/sm8250/xiaomi/elish/` | Extracted from the unit's vendor/persist partitions. `adsp`/`venus` are a **different MIUI revision** than `lujianhua/xiaomi-elish-firmware` (verified by md5); `a650_zap.mbn` is byte-identical to upstream. |
| `cirrus/` | `cs35l41-dsp1-spk-prot.wmfw` + 8 position `*.bin` | `/usr/lib/firmware/cirrus/` | Byte-identical to `lujianhua/xiaomi-elish-firmware` (verified). Xiaomi's speaker-protection tuning for the 8× CS35L41 amps. |
| `novatek/` | `nt36523-csot.bin`, `nt36523-boe.bin` | `/usr/lib/firmware/novatek/` | csot: byte-identical to upstream. boe: taken from `lujianhua/xiaomi-elish-firmware` for BOE-panel units (the device ships with either panel). |
| `qcom/` | `a650_gmu.bin`, `a650_sqe.fw` | `/usr/lib/firmware/qcom/` | Adreno 650 GPU firmware. On the working unit these are **not** owned by any package — mirrored here for completeness. |
| `hexagonfs/` | `sensors/config`, `sensors/registry`, `socinfo` | `/usr/share/qcom/sm8250/Xiaomi/elish/` | Sensor hub registry + platform info used by the SLPI DSP; subset of upstream hexagonfs actually present on the working unit. |

## Not included (and why)

- `wlanmdsp`/ath11k board data — provided by `linux-firmware` / `ath11k` packages
- Per-device calibration (persist partition speaker cal, Wi-Fi MAC) — unique to
  each unit, extracted at runtime; the ath11k MAC is worked around by
  `configs/etc/systemd/network/10-ath11k.link`

## Completeness check

On the reference unit, every file under `/usr/lib/firmware` not owned by a
package is mirrored here (`qcom/sm8250/xiaomi/elish`, `cirrus/cs35l41*`,
`novatek`, `qcom/a650*`), plus the `hexagonfs` subset under
`/usr/share/qcom`. Everything else comes from `linux-firmware`/`alsa-firmware`.

## Upstream references

- <https://github.com/lujianhua/xiaomi-elish-firmware> — canonical dump used
  by postmarketOS `firmware-xiaomi-elish`
- pmOS pmaports package: `device/testing/firmware-xiaomi-elish`
