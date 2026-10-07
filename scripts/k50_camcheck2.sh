#!/bin/bash
# Does this kernel tree carry mainline's MediaTek ISP driver (mtk-isp, the
# MT8183/MT8195 one), and what MIPI CSI-2 RX plumbing exists?
set -u
L=${HOME}/work/mt6895-mainline/linux
cd "$L" || exit 1

echo "=== grep for mt8195/mt8183 camsys & isp bindings anywhere ==="
grep -rl --include='*.c' --include='*.h' --include='*.yaml' --include='Kconfig' --include='Makefile' \
	-e 'mt8195-camsys' -e 'mt8183-camsys' -e 'mtk-isp' -e 'mtk_isp' \
	drivers/ Documentation/ include/ 2>/dev/null | head -20
echo "(empty = no mainline ISP driver in this tree)"

echo
echo "=== MIPI CSI-2 RX / seninf plumbing present? ==="
ls drivers/phy/mediatek/ 2>/dev/null | grep -i -E 'csi|mipi|dphy' || echo "  (no csi phy driver)"
ls drivers/media/platform/mediatek/ 2>/dev/null
grep -n -i -E 'mipi-csi|csi2|seninf' drivers/phy/mediatek/Kconfig 2>/dev/null | head

echo
echo "=== is there a camera/ISP node in mt6895.dtsi at all? ==="
grep -n -i -E 'camisp|seninf|mipi.*csi|csi.*rx|imgsensor' arch/arm64/boot/dts/mediatek/mt6895.dtsi 2>/dev/null | head -10
echo "--- sensor/cci bus nodes in mt6895.dtsi ---"
grep -n -i -E 'cci|i2c[0-9]+@.*(1a0|11c)' arch/arm64/boot/dts/mediatek/mt6895.dtsi 2>/dev/null | head -10

echo
echo "=== camera-related vendor modules in the extraction package ==="
find ${K50_REPO}/Redmi_K50_驱动提取包/03_内核模块 -maxdepth 2 -iname '*cam*' -o -maxdepth 2 -iname '*imgsensor*' -o -maxdepth 2 -iname '*imx*' -o -maxdepth 2 -iname '*seninf*' 2>/dev/null | head -15
echo "--- package subdirs ---"
ls ${K50_REPO}/Redmi_K50_驱动提取包/03_内核模块 2>/dev/null | head -20
