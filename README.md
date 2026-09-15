# android_device_nubia_nx563j
Tree for building TWRP for Nubia Z17 (Decryption works on Android 11/12.x/13.x ROMs)

## Kernel Sources

https://github.com/Cyborg2017/android_kernel_nubia_msm8998-oss/tree/lineage-20.0

## To compile

export ALLOW_MISSING_DEPENDENCIES=true

. build/envsetup.sh && lunch twrp_nx563j-eng

mka adbd recoveryimage

## Decrypting the encrypted /data partition (QSEE)

Most devices ship with an encrypted `userdata` partition. On Qualcomm
(MSM8998) devices the encryption key material is protected by the QSEE
(Qualcomm Secure Execution Environment), so TWRP must bring its own copy of
the QSEE user-space stack into the recovery ramdisk to unlock and mount
`/data` during decryption. All required components are shipped prebuilt in
`recovery/root`:

| Component | Stock ROM path | Ramdisk path |
|-----------|----------------|--------------|
| `qseecomd` (decryption daemon) | `/system/bin/qseecomd` | `system/bin/qseecomd` |
| `libQSEEComAPI.so` | `/vendor/lib64/libQSEEComAPI.so` | `vendor/lib64/libQSEEComAPI.so` |
| `libdrmfs.so` | `/vendor/lib64/libdrmfs.so` | `vendor/lib64/libdrmfs.so` |
| Keystore HAL | `/vendor/lib64/hw/keystore.msm8998.so` | `vendor/lib64/hw/keystore.msm8998.so` |
| Keymaster HAL service | `/system/bin/android.hardware.keymaster@3.0-service` | `system/bin/android.hardware.keymaster@3.0-service` |
| Gatekeeper HAL service | `/system/bin/android.hardware.gatekeeper@1.0-service` | `system/bin/android.hardware.gatekeeper@1.0-service` |
| VINTF manifests | vendor + system | `vendor/etc/vintf/manifest.xml`, `system/etc/vintf/manifest.xml` |

### How it is wired up

Decryption uses TWRP's standard Qualcomm flow (`BOARD_USES_QCOM_FBE_DECRYPTION
:= true` in `BoardConfig.mk`, provided by `device/qcom/twrp-common`):

1. `init.recovery.qcom.rc` imports the auto-generated
   `init.recovery.qcom_decrypt.rc`, which registers the `prepdecrypt`,
   `qseecomd` and per-version keymaster services and fixes up the device
   nodes (`/dev/qseecom`, `/dev/ion`) and permissions needed by QSEE.
2. TWRP's partition manager detects the keymaster version from the vendor
   VINTF manifest (`android.hardware.keymaster@3.0` here) and starts the
   matching HAL service; `qseecomd` then talks to the TZ firmware through
   `/dev/qseecom`.
3. `/data` is unlocked with the keystore key, mounted and made available to
   the rest of the UI (`fileencryption=ice` FBE on msm8998).

Notes for maintenance:

- The stock binaries were built with `/system/bin/linker64` as dynamic
  interpreter, which matches the linker TWRP 12.1 ships in its ramdisk — no
  `patchelf --set-interpreter` step is needed (older TWRP used `/sbin`).
  Run `readelf -l` on a blob after replacing it from a newer ROM to confirm.
- Legacy flags from older guides (`TARGET_PROVIDES_KEYMASTER`,
  `TARGET_KEYMASTER_WAIT_FOR_QSEE`) no longer exist in the TWRP 12.1/14
  sources and must not be re-added; `BOARD_USES_QCOM_FBE_DECRYPTION` is the
  only switch.
- After swapping any blob from a newer ROM, run
  `scripts/verify_qsee_decrypt.sh` to re-check file presence, interpreter
  paths and the NEEDED library closure.

### Debugging a failed decryption

- On boot: a fast splash screen followed by a password prompt (when no lock
  was set) means decryption failed; a longer splash and
  `Data successfully decrypted` in the TWRP log means it worked.
- `qseecomd` writes to both the kernel log and logcat: use `dmesg` or
  `logcat` (logcat support is enabled via `TWRP_INCLUDE_LOGCAT` /
  `TARGET_USES_LOGD` in `BoardConfig.mk`).
- TWRP's own decryption attempt is recorded in `/cache/recovery/last_log*`.

## Device specifications

ZTE Nubia Z17 (codenamed "nx563j") is a high-range smartphone from Nubia.
It was released in June 2017.

Basic   | Spec Sheet
-------:|:-------------------------
CPU     | Quad-core 2.45 GHz Kryo 280 & Quad-core 1.9 GHz Kryo 280
Chipset | Qualcomm MSM8998 Snapdragon 835
GPU     | Adreno 540
Memory  | 6/8 GB RAM
Android Version | 7.1.1
Storage | 64/128 GB
Battery | Li-Ion 3200mAh battery
Display | 1080 x 1920 pixels, 5.5 inches
Back camera  | Dual 23/12 MP, f/1.8, phase detection autofocus, dual-LED (dual tone) flash
## Device picture

![ZTE Nubia Z17](http://www.ixbt.com/short/images/2017/Jun/Nubia-Z17-official-01.jpg "ZTE Nubia Z17")
