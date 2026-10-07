#!/bin/bash
# Route-C feasibility: what does mainline already have for the pieces the
# camera needs on this board?
set -u
L=${HOME}/work/mt6895-mainline/linux
cd "$L" || exit 1

echo "=== i2c controller: which MediaTek compatibles does mainline support? ==="
grep -n -E 'mediatek,mt[0-9]+-i2c' drivers/i2c/busses/i2c-mt65xx.c | tail -25

echo
echo "=== is the camera LDO PMIC (fan53870) in mainline? ==="
grep -rli --include='*.c' --include='*.h' --include='Kconfig' -e 'fan53870' -e 'onsemi,fan' drivers/ 2>/dev/null | head
echo "(empty = not supported)"

echo
echo "=== other camera rails: what are the phandles 0x2f2/0x2f3/0x31a on this board? ==="
grep -n -E 'phandle = <0x2f2>|phandle = <0x2f3>|phandle = <0x31a>|phandle = <0x2f4>|phandle = <0x2f5>|phandle = <0x2fe>|phandle = <0x2ff>' \
	${K50_REPO}/out/orig_live.dts | head -12

echo
echo "=== what regulators are those nodes? (context around each hit) ==="
for p in 2f2 2f3 31a 2f4 2f5 2fe 2ff; do
	echo "--- phandle <0x$p>"
	n=$(grep -n "phandle = <0x$p>" ${K50_REPO}/out/orig_live.dts | head -1 | cut -d: -f1)
	if [ -n "$n" ]; then
		start=$((n - 30))
		sed -n "${start},${n}p" ${K50_REPO}/out/orig_live.dts \
			| grep -E '^\s+[a-z0-9_,@-]+ \{$|compatible|regulator-name|regulator-min-microvolt' | tail -4
	fi
done

echo
echo "=== camera clock (topckgen) ids used as mclk ==="
grep -n -E '"mclk"' ${K50_REPO}/out/orig_live.dts | head -6
echo "--- clock-names list for cam0..3 ---"
grep -n 'clock-names = "6\\012' ${K50_REPO}/out/orig_live.dts | head -6

echo
echo "=== mt6895 cam clock driver in mainline? ==="
ls drivers/clk/mediatek/ | grep -i -E 'mt6895|mt6983'

echo
echo "=== power domains the camsys needs (mt6895.dtsi) ==="
grep -n -E 'cam_main|cam_suba|cam_subb|cam_subc|cam_vcore|cam_mraw' \
	arch/arm64/boot/dts/mediatek/mt6895.dtsi | head -12
