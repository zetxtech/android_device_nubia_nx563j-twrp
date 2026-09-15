#!/usr/bin/env bash
#
# Verify the QSEE decryption port in this TWRP device tree.
#
# Checks that every component required to decrypt an encrypted /data on
# Qualcomm (QSEE) devices is present in recovery/root, that dynamic
# interpreters point to a linker TWRP actually provides, and that the
# NEEDED dependency closure of the ported blobs can be satisfied by the
# ramdisk plus the libraries TWRP's build system injects automatically.
#
# Usage: scripts/verify_qsee_decrypt.sh [path-to-device-tree]
#        (defaults to the repository root)

set -u
DEV=${1:-$(cd "$(dirname "$0")/.." && pwd)}
ROOT="$DEV/recovery/root"

# Non-identical binaries from the stock ROM that form the QSEE decryption
# stack. Paths are relative to the ramdisk root.
REQUIRED_FILES=(
    "system/bin/qseecomd"
    "vendor/lib64/libQSEEComAPI.so"
    "vendor/lib64/libdrmfs.so"
    "vendor/lib64/hw/keystore.msm8998.so"
    "vendor/lib64/hw/android.hardware.keymaster@3.0-impl.so"
    "vendor/lib64/hw/android.hardware.gatekeeper@1.0-impl.so"
    "system/bin/android.hardware.keymaster@3.0-service"
    "system/bin/android.hardware.gatekeeper@1.0-service"
    "vendor/etc/vintf/manifest.xml"
    "system/etc/vintf/manifest.xml"
    "init.recovery.qcom.rc"
    "ueventd.qcom.rc"
)

# Libraries the TWRP build system pulls into the ramdisk itself
# (bootable/recovery/prebuilt/Android.mk, external/e2fsprogs, AOSP), so they
# do not have to ship in the device tree.
TWRP_PROVIDED_LIBS=(
    libc.so libm.so libdl.so liblog.so libcutils.so libutils.so libc++.so
    libbase.so libz.so libcrypto.so libexpat.so libfs_mgr.so liblp.so
    libfstab.so libprocessgroup.so libprocessgroup_setup.so
    libpackagelistparser.so libvndksupport.so libvintf.so libxml2.so libion.so
    libhardware.so libhwbinder.so libhidlbase.so libhidltransport.so
    libhidlmemory.so libkeymaster_messages.so libkeymaster_portable.so
    libkeymaster_staging.so libkeymaster4support.so libkeymaster4_1support.so
    libsoftkeymasterdevice.so libpuresoftkeymasterdevice.so
    lib_android_keymaster_keymint_utils.so
    android.hardware.keymaster@3.0.so android.hardware.gatekeeper@1.0.so
    vendor.display.config@1.0.so vendor.display.config@2.0.so
    libsoft_attestation_cert.so
    libbinder.so libbinder_ndk.so libunwindstack.so libprocinfo.so
    libdebuggerd_client.so libdebuggerd.so
    libext2_uuid.so libext2fs.so libext2_blkid.so libext2_com_err.so
    libext2_e2p.so libext2_quota.so libext2_swapfs.so
)

fail=0
warn=0

say()  { printf '%-8s %s\n' "$1" "$2"; }

check_file() {
    if [ -e "$ROOT/$1" ]; then
        say PASS "$1"
    else
        say FAIL "$1"
        fail=$((fail + 1))
    fi
}

echo "== 1. Required QSEE components =="
for f in "${REQUIRED_FILES[@]}"; do
    check_file "$f"
done

echo
echo "== 2. Dynamic interpreter (must match the TWRP linker) =="
while IFS= read -r bin; do
    interp=$(readelf -l "$bin" 2>/dev/null |
        sed -n 's/.*Requesting program interpreter: \(.*\)/\1/p' | tr -d ']')
    case "$interp" in
        /system/bin/linker64|/sbin/linker64|/system/bin/linker|/sbin/linker)
            say PASS "${bin#$ROOT/} -> $interp"
            ;;
        "")
            say WARN "${bin#$ROOT/}: no PT_INTERP (not an executable)"
            warn=$((warn + 1))
            ;;
        *)
            say FAIL "${bin#$ROOT/}: interpreter '$interp' not provided by TWRP"
            fail=$((fail + 1))
            ;;
    esac
done < <(find "$ROOT/system/bin" -type f -executable)

echo
echo "== 3. NEEDED dependency closure =="
known=()
while IFS= read -r -d '' so; do
    known+=("$(basename "$so")")
done < <(find "$ROOT" -name '*.so' -print0)
known+=("${TWRP_PROVIDED_LIBS[@]}")

# Missing libs: NEEDED entry not found in the ramdisk nor provided by the
# TWRP build system. Report each requested lib only once (unique names).
miss=0
while read -r lib; do
    found=0
    for k in "${known[@]}"; do
        [ "$k" = "$lib" ] && { found=1; break; }
    done
    if [ "$found" -eq 0 ]; then
        say MISSING "$lib"
        miss=$((miss + 1))
    fi
done < <(find "$ROOT" \( -name '*.so' -o -path '*system/bin*' -type f \) -print0 |
    while IFS= read -r -d '' f; do
        readelf -d "$f" 2>/dev/null |
        sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'
    done | sort -u)

if [ "$miss" -eq 0 ]; then
    say PASS "all NEEDED libraries resolvable"
else
    fail=$((fail + miss))
fi

echo
echo "== 4. keymaster version vs. vendor manifest =="
vmajor=$(grep 'IKeymasterDevice' \
    "$ROOT/vendor/etc/vintf/manifest.xml" 2>/dev/null |
    grep -o '@[0-9.]*::' | head -1 | tr -d '@:')
echo "  vendor manifest: android.hardware.keymaster@${vmajor:-?}"
case "${vmajor:-}" in
    3.0)
        check_file "system/bin/android.hardware.keymaster@3.0-service"
        check_file "vendor/lib64/hw/android.hardware.keymaster@3.0-impl.so"
        ;;
    4.0|4.1)
        check_file "system/bin/android.hardware.keymaster@4.0-service"
        ;;
    *)
        say WARN "unknown keymaster version; please add matching HAL service"
        warn=$((warn + 1))
        ;;
esac

echo
echo "== Result =="
if [ "$fail" -eq 0 ]; then
    echo "OK: QSEE decryption stack is complete and consistent"
    exit 0
else
    echo "FAILED: $fail missing/inconsistent item(s), $warn warning(s)"
    exit 1
fi