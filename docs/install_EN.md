# Install: stock Android → Arch Linux ARM

Tested on a 16GB RAM-modded unit with the CSOT panel; Android stays on slot A
and Linux boots from slot B. No teardown or SD card needed (elish has none) —
just a PC and a USB-C cable.

## 0. Prerequisites: unlock + backup

```text
PC tools          → adb + fastboot (`pacman -S android-tools` on Arch)
Bootloader unlock → official Mi Unlock (first unlock has a waiting period)
Enter fastboot    → power off, then Vol- + Power; or `adb reboot bootloader`
```

**Back up before touching anything.** The proven method: in Recovery (§1)
with an ADB root shell, dd every partition out plus the GPT header/trailer:

```sh
# recovery shell (root), per partition:
dd if=/dev/block/sdaN of=/sdcard/bkparts/<name>.img
# GPT head AND tail (the trailer is the backup table — lose it too):
dd if=/dev/block/sda of=gpt-head.bin bs=512 count=34
sgdisk -b /sdcard/bkparts/gpt-full.bin /dev/block/sda   # head+tail in one file
# also keep a standalone persist.img (calibration data — lose it and your
# Wi-Fi MAC / sensor calibration is gone)
```

Pull backups off-device (`adb pull`). **Do not continue without a persist backup.**

## 1. Partitioning (inside Recovery)

A factory device is all Android partitions. The approach: **shrink userdata and
append two partitions at the end of the disk** — no Android system partition is
touched; the only cost is a userdata rebuild (data wipe; back up MIUI data
separately).

You need an environment that gives `adb shell` root. We used
[web1n's unofficial LineageOS for elish](https://xdaforums.com/t/rom-unofficial-a16-elish-lineageos-23-2-for-xiaomi-pad-5-pro-wifi.4764518/) —
elish is A/B, the recovery ramdisk lives inside `boot.img`; per the release
notes `fastboot flash` it, then reboot into recovery (**elish's bootloader
refuses `fastboot boot` — flash only**).
**Any environment with a root shell plus sgdisk/mkfs works** (a rooted Android
system is fine too).

```sh
adb shell
# verify numbering first — never guess:
ls -l /dev/block/by-name/ | grep userdata     # → sda34
sgdisk -p /dev/block/sda                      # inspect current layout
```

```sh
# step 1: read partition 34's actual start sector (Number/Start/End columns)
sgdisk -p /dev/block/sda
# say 34's Start=22589440 (use YOUR value, not this one).
# shrink userdata to 200G: 200*1024^3/512 = 419430400 sectors,
# new End = Start + 419430400 - 1 → e.g. Start=22589440 → End=442019839
sgdisk -d 34 -n 34:22589440:442019839 -c 34:userdata /dev/block/sda
# step 2: append at the tail (auto-picks the first free start)
sgdisk -n 0:0:+1G -c 0:esp   -t 0:EF00 /dev/block/sda   # → sda35
sgdisk -n 0:0:0    -c 0:linux -t 0:8300 /dev/block/sda  # → sda36, takes the rest
mkfs.vfat -F32 /dev/block/sda35
mkfs.ext4      /dev/block/sda36
```

> The PARTLABELs **must** be `esp` and `linux` (fstab and the kernel cmdline
> find disks by label). Android will ask to Format Data afterwards — expected.

**Missing tools in recovery** (third-party recovery toybox often lacks
`sgdisk`/`mkfs.vfat`):

- no sgdisk → grab a **static aarch64 sgdisk** on the PC, `adb push` it to
  `/tmp`, `chmod +x` and run it there
- no mkfs.vfat → build a 1G FAT32 image on the PC (`mkfs.vfat`/mtools),
  `adb push` and `dd of=/dev/block/sda35`
- no mkfs.ext4 → same: prebuild the ext4 image on the PC and dd it (ext4 must
  exist before the rootfs step)

Resulting layout (measured on the test device):

| PARTLABEL | Partition | Size | FS | Purpose |
|---|---|---|---|---|
| userdata | sda34 | ~200G | f2fs | Android data (shrunk) |
| `esp` | sda35 | 1G | FAT32 | mounted at `/boot`; Image/dtb/menu |
| `linux` | sda36 | rest | ext4 | Arch rootfs |

## 2. Rootfs (push + extract in Recovery)

Download the [generic ALARM aarch64 rootfs](https://archlinuxarm.org/platforms/armv8/generic)
(`ArchLinuxARM-aarch64-latest.tar.gz`) on the PC, then:

```sh
# recovery shell:
mount /dev/block/sda36 /tmp/mnt
adb push ArchLinuxARM-aarch64-latest.tar.gz /tmp/mnt/rootfs.tar.gz
tar -xpf /tmp/mnt/rootfs.tar.gz -C /tmp/mnt && rm /tmp/mnt/rootfs.tar.gz
mount /dev/block/sda35 /tmp/mnt/boot   # mount ESP at the rootfs's /boot
```

## 3. Deploy repo files

Two stages. **The ESP payload and fstab must be in place from Recovery** —
SimpleInit reads the kernel via `@esp:/Image`, so an empty ESP means first
boot fails outright. §2 already mounted sda36→`/tmp/mnt` and
sda35→`/tmp/mnt/boot`. Push the repo into the rootfs (e.g.
`adb push elish-alarm /tmp/mnt/root/`), **cd into the repo directory**, then
run in the recovery shell (no sudo):

```sh
cp esp/* /tmp/mnt/boot/                 # full ESP: Image+menu+both dtbs+SwitchSlotsApp
cp configs/etc/fstab /tmp/mnt/etc/fstab # PARTLABEL mounts, no UUID edits
```

**Everything else waits until after first Linux boot** (sudo exists, depmod
works, paths are real). With this repo cloned/copied into the rootfs:

```sh
sudo mkdir -p /lib/modules/7.2.0-elish-arm64
sudo cp -a modules/. /lib/modules/7.2.0-elish-arm64/  # kernel modules, same build as esp/Image
sudo depmod -a
```

> To re-verify the ESP contents afterwards: `sudo mount /boot` (already
> mounted automatically once fstab is in effect) then `sudo cp esp/* /boot/`
> to top up.
> If you insist on finishing the rest inside Recovery: prefix every target
> with the rootfs mount — `/etc`→`/tmp/mnt/etc`,
> `/lib/modules`→`/tmp/mnt/usr/lib/modules` — drop `sudo`, and run `depmod`
> after first boot. Copying the commands verbatim writes files into
> Recovery's own tmpfs — gone on reboot.

No clone, Release-tarball only: the module tree is equivalent to
`sudo tar -xJf modules-7.2.0-elish-arm64.tar.xz -C /usr/lib/modules/`
(note `/usr/lib/modules`, **not `-C /`** — the tarball's top level is the
versioned directory).

> If you insist on doing this inside Recovery: prefix targets with the
> rootfs mount — `/boot`→`/tmp/mnt/boot`, `/etc`→`/tmp/mnt/etc`,
> `/lib/modules`→`/tmp/mnt/usr/lib/modules`, drop `sudo`, and run `depmod`
> after first boot. Copying the commands verbatim writes files into
> Recovery's own tmpfs — gone on reboot.

> `Image` only lights the machine up — **Wi-Fi/audio/touch drivers all live in
> `modules/`** (built as `=m`). Skip it and you get a device that
> boots but does nothing.

Set your panel in `esp/simpleinit.uefi.cfg`'s `dtb` line
(`elish-csot.dtb` ↔ `elish-boe.dtb`).

## 4. Firmware + audio

```sh
sudo install -Dm644 firmware/sm8250/* -t /usr/lib/firmware/qcom/sm8250/xiaomi/elish/
sudo install -Dm644 firmware/qcom/*    -t /usr/lib/firmware/qcom/
sudo install -Dm644 firmware/cirrus/*  -t /usr/lib/firmware/cirrus/
sudo install -Dm644 firmware/novatek/* -t /usr/lib/firmware/novatek/
sudo cp -a firmware/hexagonfs/. /usr/share/qcom/sm8250/Xiaomi/elish/
```

Three ingredients for audio:

- `firmware/sm8250/adsp*` + `firmware/cirrus/cs35l41*` — DSP and amplifier blobs
- UCM2 routes (**including the conf.d symlink**, or the card won't match):
  ```sh
  sudo cp -r configs/usr/share/alsa/ucm2/Xiaomi/elish /usr/share/alsa/ucm2/Xiaomi/
  sudo cp -a configs/usr/share/alsa/ucm2/conf.d /usr/share/alsa/ucm2/
  ```
- The three `kernel/patches/` are **required for correct playback**
  (S16 depth limit, L/R channel map, PUP timeout→warn) — if you build your own
  kernel, apply them

## 5. Wi-Fi (three hardware quirks)

```sh
sudo cp configs/etc/systemd/network/10-ath11k.link /etc/systemd/network/
sudo cp configs/etc/systemd/system/pcie-rescan.service /etc/systemd/system/
sudo cp -r configs/etc/systemd/system/iwd.service.d /etc/systemd/system/
sudo systemctl enable iwd pcie-rescan
```

| File | Quirk it fixes |
|---|---|
| `10-ath11k.link` | ath11k reports an all-zero permanent MAC; repo default `MACAddressPolicy=persistent` derives a unique stable local address from machine-id |
| `pcie-rescan.service` | QCA6390 PCIe link training sometimes fails and wlan0 never appears — rescans the bus up to 10 times at boot |
| `iwd` drop-in | iwd races udev and grabs the interface before the MAC is applied — makes it wait for wlan0 |

**Two MAC options**:

- Repo default `MACAddressPolicy=persistent` — unique per device, zero config; **not verified on real hardware** (driver-agnostic, should work)
- The test device uses its **fixed factory MAC** (the real Android MAC — verified): use the `10-ath11k.factory-mac.link.example` template — fill in your factory MAC, then rename it to `10-ath11k.link` replacing the default file. The MAC lives in the `persist` partition at `wlan/wlan_mac.bin` (format `wlan0=AABBCCDDEEFF`)

**Online on first boot**: write credentials into the rootfs beforehand and iwd
auto-connects:

```ini
# /var/lib/iwd/<YourSSID>.psk
[Security]
Passphrase=YourWiFiPassword
```

iwd is not in the ALARM base — with no network you can't install it. Two ways
out:

- **Preinstall (recommended)**: download the aarch64 `iwd` package and its
  `ell` dependency from an ALARM mirror on the PC, drop them into the rootfs
  alongside the psk, then inside the system:
  ```sh
  sudo pacman -U /tmp/ell-*.pkg.tar.zst /tmp/iwd-*.pkg.tar.zst
  sudo systemctl enable --now iwd
  ```
- **Fallback**: first boot with a USB-C Ethernet adapter or phone USB
  tethering, then `pacman -S iwd` normally.

ALARM default accounts are `alarm:alarm` and `root:root` (sshd is enabled in
base — ssh works as soon as wlan0 is up).

**Bluetooth (QCA6390 ships with no address)**: after power-up `hci0`
registers with an all-zero BDADDR, the kernel marks it "unconfigured" and
`bluetoothctl` shows **no controller at all** (`No default controller
available`) even though firmware download succeeded in dmesg. The fix is to
program the factory address. The repo ships a script + service:

```sh
sudo install -Dm755 configs/usr/local/bin/elish-btaddr.sh -t /usr/local/bin/
sudo cp configs/etc/systemd/system/elish-btaddr.service /etc/systemd/system/
sudo systemctl enable --now elish-btaddr.service
```

Default is dynamic mode: the script reads this unit's factory address from
persist `bluetooth/.bt_nv.bin` (6 raw bytes, = Wi-Fi MAC+1) — zero
configuration on any device. To hardcode instead, use the
`elish-btaddr.service.d/override.conf.example` template — fill in your
factory BT MAC and drop the `.example` suffix (i.e. `override.conf`;
equivalent to writing it via `systemctl edit elish-btaddr`):

```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/elish-btaddr.sh YOUR_FACTORY_BT_MAC
```

Verify: `bluetoothctl show` should list the `elish` controller with
`Powered: yes`, and `bluetoothctl scan on` finds nearby devices.

## 5.5 Sensors + A/B slot (optional, strongly recommended)

elish's accelerometer/gyroscope/light/magnetometer are hosted by the SLPI
(sensor low-power island). Without the userspace daemon, SLPI **crashes and
restarts roughly every 40 seconds** (`crash detected in slpi` in dmesg).
Complete the chain: install `hexagonrpcd` (feeds the hexagonfs registry to
the DSP) + `qbootctl` (slot marking) + `libssc` (sensor-to-userspace bridge —
the official repo `libssc` or AUR `libssc-git`). All three live in the AUR —
a fresh ALARM has no AUR helper, so `sudo pacman -S --needed base-devel git`
first and build with `makepkg -si` per the AUR workflow (or install yay):

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

| File | Purpose |
|---|---|
| `/etc/conf.d/hexagonrpcd-sdsp` | Points the daemon at the hexagonfs registry; **the service fails to start without it** |
| `61-libssc.rules` | Tags fastrpc devices with `IIO_SENSOR_PROXY_TYPE` (the proxy's accel driver claims devices by this tag) + `ACCEL_MOUNT_MATRIX` |
| `qbootctl.service` | Marks the current slot successful every boot — without it the retry counter runs out and the bootloader **flips back to the Android slot** |
| fstab `persist` line | SLPI reads/writes `/mnt/vendor/persist/sensors` calibration data; unmounted = crash loop returns |
| `hexagonrpcd-sdsp` drop-in `restart.conf` | `Restart=always` — the daemon occasionally **exits cleanly** (status 0, after tens of minutes); systemd treats that as "done" and never restarts it, then the SLPI watchdog crash-loops and all sensors silently die (the errors point elsewhere — very hard to trace). It must come back every time |
| `hexagonrpcd-sdsp` drop-in `persist-perms.conf` | **Every Android boot re-owns the sensor registry to the Android user**, after which the daemon (fastrpc group) can't write it. This drop-in runs `chgrp fastrpc + g+rw` as root before each daemon start — immune to Android/Arch switching |
| `75-elish-ignore-tablet-mode.rules` (plasma-mobile only) | The pogo keyboard controller (`3206:3ffc`) always enumerates mouse/touchpad interfaces, making KWin decide "not a tablet" → auto-rotation never engages. The `kwin-ignore-tablet-mode` tag removes it from the check |
| `49-sensor-proxy-claim.rules` (plasma-mobile only) | polkit only allows sensor claims from the active seat session; early-login claims hit the still-active greeter and get denied. Unconditionally allow, preventing random loss of rotation or its UI toggle |
| `elish-qs-accel.service` + `elish-qs-wait-accel.sh` (plasma-mobile only, user unit) | The quicksettings model permanently filters out plugins that are "unavailable" at list-build time — and hexagonrpcd takes ~55s to init, so the panel almost always wins the race. This service polls the accel; if the race was lost it restarts plasmashell once after the sensor is ready, otherwise it exits quietly |
| `iio-sensor-proxy` drop-in | A fuse: if the sensor stack misbehaves (persist unmounted, daemons missing) the proxy stops responding and stalls shutdown for the default 90s — this caps it at 10s; does nothing when the stack is healthy |

After mounting, **fix permissions once** — the sensor registry in persist is
owned by Android's system user (uid 1000, shows as a regular user here), and
the daemon runs as `fastrpc` so it can't write (log spams
`Tried to open … temp.json`):

```sh
sudo chgrp -R fastrpc /mnt/vendor/persist/sensors/registry
sudo chmod -R g+rw /mnt/vendor/persist/sensors/registry
sudo find /mnt/vendor/persist/sensors/registry -type d -exec chmod g+s {} +
```

(changes group only, owner untouched — Android unaffected; setgid makes new
files inherit the fastrpc group. From then on the `persist-perms.conf`
drop-in repairs it on every Arch boot — **Android resets the owner every
time it boots**, so a one-off manual fix only lasts until the next switch)

⚠️ The mount matrix **is calibrated on real hardware**: the repo uses
`"-1, 0, 0; 0, -1, 0; 0, 0, 1"` (X/Y negated, Z kept) — postmarketOS's
all-negated matrix misreads face-up as face-down on this unit. Verify with
`sudo monitor-sensor`: portrait port-down → `normal`, landscape port-right →
`right-up`, lying flat face-up → `face-up`.

**KDE auto-rotation**: Plasma only consumes orientation data in touch mode —
Settings → Workspace Behavior → General Behavior → set **Touch Mode to
"Always enable"**; keep the display's autoRotation at `InTabletMode`
(effectively permanent tablet).

**iio-sensor-proxy upstream race bug (patch required, or rotation very
likely fails).** In 3.9 the proxy registers its D-Bus object first and
enumerates sensors later (SSC enumeration takes ~1s, one QMI round-trip
per sensor). KDE claims the accelerometer the instant the D-Bus name
appears — always before enumeration finishes: the claim is recorded in
the clients table and returns success, but with the device not yet bound,
polling never starts; the coldplug bind path **does not re-check the
clients table** (the hotplug path does — coldplug was missed), leaving
`Has accelerometer` with orientation/tilt stuck at `undefined`.
The repo ships the patch
`patches/iio-sensor-proxy/0001-poll-sensors-claimed-during-enumeration.patch`
(re-checks the clients table after enumeration and starts polling). Apply
it like this:

```sh
git clone --depth 1 -b 3.9 https://gitlab.freedesktop.org/hadess/iio-sensor-proxy.git
cd iio-sensor-proxy
patch -p1 < /path/to/0001-poll-sensors-claimed-during-enumeration.patch
meson setup build -Dssc-support=enabled   # auto mode skips the SSC drivers
ninja -C build
sudo systemctl stop iio-sensor-proxy
sudo cp build/src/iio-sensor-proxy /usr/lib/iio-sensor-proxy
sudo systemctl start iio-sensor-proxy
```

The patch replaces a package-owned binary — **pacman upgrades will revert
it**. Freeze the package until upstream merges (the patch mirrors existing
hotplug-path logic, so it's MR-worthy):

```sh
# /etc/pacman.conf
IgnorePkg = iio-sensor-proxy
```

Verify the fix took: `journalctl -u iio-sensor-proxy` should show
`claimed during enumeration, starting polling` and
`Enabling sensor ... continuous`.

**Troubleshooting: other causes of accel-present-but-no-data.** If
`monitor-sensor` shows `Has accelerometer` yet orientation/tilt stays
`undefined` (while `ssccli` streams fine), besides the race above the QMI
subscription may be stale — after the proxy gets SIGKILLed, SLPI keeps a
dead subscription and enable requests go unanswered. **Don't SIGKILL**:
`sudo systemctl restart hexagonrpcd-sdsp iio-sensor-proxy` (restarting the
daemon lets the DSP notice the dead link); reboot if that fails. The
repo's proxy drop-in adds `After=/Wants=hexagonrpcd-sdsp` for correct
ordering. For debugging, enable verbose proxy logs via
`systemctl edit iio-sensor-proxy` with `[Service]` and
`Environment=G_MESSAGES_DEBUG=all`.

⚠️ **Suspend is currently broken**: after s2idle resume the QMI/sensor
subscription state is unrecoverable — the SLPI crash loop returns, and
restarting daemon/proxy or resetting the remoteproc cannot fix it; only a
full reboot recovers. Recommend masking it and using screen-off only:

```sh
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Plasma Mobile auto-rotation (optional session)

`pacman -S plasma-mobile` adds a Plasma Mobile session to the login manager
(it coexists with desktop Plasma; layouts don't interfere). Mobile rotation
depends entirely on KWin's tablet-mode detection, and this device has two
hardware quirks that must be fixed or rotation dies:

**The pogo keyboard controller fakes a mouse (required).** The keyboard
connector's USB controller (Xiaomi `3206:3ffc`) always enumerates
keyboard+mouse+touchpad HID interfaces, whether or not a keyboard is
attached. KWin computes `isTablet = hasTouch && !hasPointer` — this phantom
pointer makes it permanently "laptop", tablet mode never engages, and the
auto-rotate pipeline never starts. Install
`configs/etc/udev/rules.d/75-elish-ignore-tablet-mode.rules` to tag that
VID:PID with `kwin-ignore-tablet-mode` (KWin's built-in opt-out tag), then
`udevadm control --reload` and log in again. Afterwards
`busctl --user get-property org.kde.KWin /org/kde/KWin
org.kde.KWin.TabletModeManager tabletMode` should return `true`.

**Early polkit claim denial (insurance).** KWin and the mobile shell may
call `ClaimAccelerometer` before the session is active, but polkit only
permits the "active session on the seat" — while the greeter session still
holds the seat, claims get `AccessDenied` and clients never retry. Symptoms
are random (rotation or the control-center rotate toggle disappears). Install
`configs/etc/polkit-1/rules.d/49-sensor-proxy-claim.rules` to unconditionally
allow that action (claiming only turns sensors on; no security impact).

**Config traps to avoid:**

- `kwinrc [Input] TabletMode=on` **does not work** — KWin reads the key with
  `readPathEntry`, which expands the relative value into `$HOME/on` so it
  never matches `"on"` (probable upstream bug). With the udev tag, `auto`
  ("on demand") already works; forced On is unnecessary.
- Editing `autoRotation` in `kwinoutputconfig.json` gets overwritten by
  KWin's in-memory state; change the policy only via System Settings →
  Display's "auto-rotate" dropdown.

## 6. Flash UEFI, first boot

The image is `edk2/boot-elish.img` in this repo (or build your own from
<https://github.com/luckyle7749/edk2-msm-elish>). One image covers all elish
RAM variants (6GB / 8GB / 16GB modded). Flash to **slot B** — Android on slot A
stays untouched:

```sh
fastboot getvar product        # must report: elish
fastboot flash boot_b edk2/boot-elish.img
fastboot set_active b
fastboot reboot
```

You'll land in the SimpleInit menu (10s timeout, defaults to Arch). First boot:
a USB-C keyboard works out of the box (drivers built-in), or ssh straight in if
you pre-provisioned iwd.

## 7. Switching back to Android

- SimpleInit menu → "Reboot to Android (switch to slot A)" runs
  `SwitchSlotsApp.efi` from the ESP
- or fastboot: `fastboot set_active a`
