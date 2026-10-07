#!/bin/bash
# What would it take to get the camera working on mainline MT6895 (rubens)?
# Checks: ISP/camsys driver presence, camera nodes in our DT, what the
# rubens-clean branch did about it, sensor driver availability, and whether the
# vendor sensor sources are available locally for register tables.
set -u
L=${HOME}/work/mt6895-mainline/linux
cd "$L" || exit 1

echo "=== mediatek media platform: is there an ISP/camsys driver? ==="
ls drivers/media/platform/mediatek/
echo "--- Kconfig entries mentioning isp/camsys/seninf ---"
grep -n -i -E 'isp|camsys|seninf|camera' drivers/media/platform/mediatek/Kconfig 2>/dev/null | head -20
echo "--- Makefile ---"
grep -n -i -E 'isp|camsys|seninf' drivers/media/platform/mediatek/Makefile 2>/dev/null | head -10

echo
echo "=== any camsys/seninf node in OUR device trees? ==="
grep -n -i -E 'camsys|seninf|camisp|imgsensor|imx582|imx596|s5k4h7|gc02m1' \
	arch/arm64/boot/dts/mediatek/mt6895*.dts arch/arm64/boot/dts/mediatek/mt6895*.dtsi 2>/dev/null | head -20
echo "(none above = our DT has no camera at all)"

echo
echo "=== mainline sensor drivers for the four rubens sensors? ==="
for s in imx582 imx596 s5k4h7 gc02m1; do
	printf '  %-8s %s\n' "$s" \
		"$(ls drivers/media/i2c/ 2>/dev/null | grep -i "^$s" | tr '\n' ' ' || true)"
done
echo "--- total mainline sensor drivers ---"
ls drivers/media/i2c/*.c 2>/dev/null | wc -l

echo
echo "=== what does the rubens-clean branch do about the camera? ==="
git show FETCH_HEAD:arch/arm64/configs/rubens.config 2>/dev/null \
	| grep -i -E 'CAMERA|MEDIA_SUPPORT|V4L2|ISP|IMX|S5K|GC02' | head -20
echo "--- camera nodes in their rubens dts ---"
git show FETCH_HEAD:arch/arm64/boot/dts/mediatek/mt6895-xiaomi-rubens.dts 2>/dev/null \
	| grep -n -i -E 'camera|camsys|seninf|imx|s5k|gc02|cci' | head -10
echo "--- camera nodes in their xaga dts (their rubens base) ---"
git show FETCH_HEAD:arch/arm64/boot/dts/mediatek/mt6895-xiaomi-xaga.dts 2>/dev/null \
	| grep -n -i -E 'camera|camsys|seninf|imx[0-9]|s5k|gc02|cci@|mipi-cci' | head -20
echo "--- any mediatek isp driver in their tree? ---"
git ls-tree FETCH_HEAD drivers/media/platform/mediatek/ 2>/dev/null
echo "--- imx582/596/s5k4h7/gc02m1 in their tree? ---"
git ls-tree FETCH_HEAD drivers/media/i2c/ 2>/dev/null | grep -i -E 'imx582|imx596|s5k4h7|gc02m1' || echo "  (none)"

echo
echo "=== local vendor sources for register tables? ==="
ls -d ${K50_REPO}/vendor_touch ${K50_REPO}/vendor_* 2>/dev/null
find ${K50_REPO} -maxdepth 2 -iname '*imgsensor*' -o -maxdepth 2 -iname '*vendor_kernel*' -o -maxdepth 2 -iname '*Kernel_OpenSource*' 2>/dev/null | head
echo "--- what is inside the extraction package? ---"
ls ${K50_REPO}/Redmi_K50_驱动提取包/ 2>/dev/null
