#!/bin/bash
# Relink the Image (the board DTB is embedded in it) after the camera DT edits,
# and repack the boot image.
set -u
WT=${K50_REPO}/rubens-clean-wt
OUT=${K50_REPO}/out
cd "$WT" || exit 1

echo "=== relink Image ==="
t0=$(date +%s)
make ARCH=arm64 LLVM=1 -j8 Image 2>&1 | tail -20
rc=${PIPESTATUS[0]}
echo "make exit=$rc took $(( $(date +%s) - t0 ))s"
[ "$rc" -eq 0 ] || { echo "BUILD FAILED"; exit 1; }
ls -la arch/arm64/boot/Image

DTB=arch/arm64/boot/dts/mediatek/mt6895-xiaomi-rubens.dtb
echo
echo "=== sanity: is the new i2c bus + vcam_ldo in the DTB? ==="
dtc -I dtb -O dts -o /tmp/cam.dts "$DTB" 2>/dev/null
grep -c 'i2c@11d03000' /tmp/cam.dts
grep -c 'vcam_ldo' /tmp/cam.dts

echo
echo "=== pack boot_cam1.img ==="
gzip -9 -c -n arch/arm64/boot/Image > "$OUT/Image.gz.cam1"
cat "$DTB" >> "$OUT/Image.gz.cam1"
cp "$OUT/Image.gz.cam1" "$OUT/Image_gz_dtb"
cd ${K50_REPO} || exit 1
python3 scripts/pack_boot_v5.py boot_cam1.img
md5sum "$OUT/boot_cam1.img"
echo "BUILDCAM1_DONE"