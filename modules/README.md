# modules/ — 内核模块树

与 `esp/Image` **同一次编译**的 `/lib/modules/7.2.0-elish-arm64` 内容。
版本戳严格绑定，不可与其他内核混用。

## 使用

```sh
sudo mkdir -p /lib/modules/7.2.0-elish-arm64
sudo cp -a modules/. /lib/modules/7.2.0-elish-arm64/
sudo depmod -a
```

> 用 Release 的 `modules-*.tar.xz` 则解压到 `/usr/lib/modules`
> （包内顶层就是版本目录）:
> `sudo tar -xpf modules-7.2.0-elish-arm64.tar.xz -C /usr/lib/modules`
> **不是** `-C /`。

## 说明

- Wi-Fi(ath11k)、声卡（snd_soc_sm8250/cs35l41)、触摸、ADSP remoteproc
  均编译为 `=m`——**不装本目录，这些硬件全部不可用**
- 已剔除 `build/`/`source/`（仅 DKMS 编译外部模块时需要，
  需要者可按 docs/kernel.md 重新构建）

Kernel module tree matching `esp/Image` (same build, vermagic-locked).
Copy to `/lib/modules/7.2.0-elish-arm64` and run `depmod -a`.
Required for Wi-Fi/audio/touch — all built as modules.
