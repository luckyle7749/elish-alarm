# elish-alarm

> **⚠️ Important: this repo's docs were AI-assisted.** A wrong partition or
> flash command can lose data or brick the device — **verify sector numbers,
> partition names and slots before running anything**; don't copy blocks
> blindly. Back up first.

[中文](README.md)

Arch Linux ARM on the Xiaomi Mi Pad 5 Pro (**elish**, Snapdragon 870 / SM8250-AC).

This repository contains everything needed to go from stock Android to a
booting Arch Linux ARM system with working hardware:

1. **UEFI firmware** — built and released separately at
   [luckyle7749/edk2-msm-elish](https://github.com/luckyle7749/edk2-msm-elish).
   Flash `boot-elish.img` to `boot_b` and keep Android on `boot_a`.
2. **Kernel** — postmarketOS SM8250 kernel (`7.2.0-dev` branch) plus three small
   local patches (see [docs/kernel.md](docs/kernel.md)). Prebuilt `Image` is in
   [esp/](esp/); the matching kernel modules are in [modules/](modules/)
   (**required** — Wi-Fi/audio/touch drivers are modules).
   ⚠️ `esp/simpleinit.uefi.cfg` pairs with this repo's `edk2/boot-elish.img`;
   older UEFI builds may not parse it — don't mix.
3. **Firmware blobs** — vendor files mirrored from a working unit under
   [firmware/](firmware/), including the CS35L41 eight-speaker audio tuning.
   Provenance and licensing notes: [firmware/README.md](firmware/README.md).

## Layout

```
edk2/      prebuilt UEFI image boot-elish.img (source: edk2-msm-elish)
kernel/    .config + local patches vs pmOS sm8250 kernel
esp/       complete ESP partition contents (Image, boot menu, both
           panel dtbs, SwitchSlotsApp)
modules/   kernel module tree (copy to /lib/modules/7.2.0-elish-arm64;
           required — Wi-Fi/audio/touch drivers live here)
firmware/  vendor blobs (DSP, audio amps, touch, sensor registry)
configs/   files that install to fixed paths on the target
           (fstab+persist, ath11k MAC fix, QCA6390 PCIe rescan, iwd, UCM2
           audio routes, sensor daemons: hexagonrpcd/libssc/qbootctl configs)
docs/      install walkthrough and per-subsystem notes
```

## Quickstart (overview)

```sh
# 1. UEFI — image in edk2/, or see edk2-msm-elish releases; slot B only
fastboot flash boot_b edk2/boot-elish.img && fastboot set_active b

# 2. Partition + Arch Linux ARM rootfs on the linux partition,
#    ESP files (Image, dtb, simpleinit.uefi.cfg) on the esp partition
#    → docs/install.md

# 3. Inside the booted system: vendor firmware + kernel on the ESP +
#    sensor / A-B slot daemons — commands in docs/install.md §4-5 and §5.5
```

Detailed walkthrough: [docs/install.md](docs/install.md)

## Tested configuration

- **Tested on**: 16GB-modified elish, CSOT panel — Arch Linux ARM + KDE Wayland
- **Provided but untested**: 6GB/8GB units, BOE panel (dtb + touch firmware
  for both panel variants are included)
- Wi-Fi needs the included `ath11k.link` MAC fix (the chip reports a zero
  permanent MAC on elish); see [docs/install.md](docs/install.md)
- Sensors (accelerometer/ambient light → auto-rotate, brightness) work:
  hexagonrpcd feeds the SLPI registry and libssc bridges it to the desktop
  (AUR packages) — see [docs/install.md](docs/install.md) §5.5. Without
  these daemons the SLPI crash-loops roughly every 40 seconds (pure battery
  drain); installing them is strongly recommended

## Licenses

Kernel patches and scripts: same terms as their upstream projects.
Vendor firmware blobs in `firmware/` remain property of their respective
owners (Qualcomm / Xiaomi / Cirrus / Novatek) and are mirrored here for
device enablement only — see [firmware/README.md](firmware/README.md).
