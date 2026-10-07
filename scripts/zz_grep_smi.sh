#!/bin/bash
K=${KDIR}
echo "=== mtk-smi.c : MMU_EN / mmu related ==="
grep -n "MMU_EN\|mmu\|SMI_LARB\|smi-common\|SMI_COMMON" $K/drivers/memory/mtk-smi.c | head -60
echo
echo "=== mtk-smi.c : larb register defines ==="
grep -n "^#define" $K/drivers/memory/mtk-smi.c | head -40
echo
echo "=== mt6895 dtsi: iommu nodes ==="
for f in $K/arch/arm64/boot/dts/mediatek/mt6895.dtsi $K/arch/arm64/boot/dts/mediatek/mt6895*.dtsi; do
	echo "--- $f"
	grep -n "iommu@\|larbs\|smi_larb\|smi-common\|camsv" "$f" 2>/dev/null | head -40
done
echo
echo "=== mtk_iommu.c : larb / mmu ctrl ==="
grep -n "MMU_CTRL\|larbs\|larb_imu\|MMU_LARB_EN\|BYPASS\|bypass" $K/drivers/iommu/mtk_iommu.c | head -50
echo
echo "=== mtk_iommu.h defines ==="
grep -n "MMU_CTRL\|MMU_LARB_EN\|BYPASS\|REG_MMU" $K/drivers/iommu/mtk_iommu.h | head -60
