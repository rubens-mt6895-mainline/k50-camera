#!/bin/bash
K=${KDIR}
echo "=== mtk_iommu_of_xlate in mtk_iommu.c ==="
awk '/^static int mtk_iommu_of_xlate\(/,/^\}/' $K/drivers/iommu/mtk_iommu.c
echo "=== mtk_iommu_of_xlate in mtk_iommu_mt6895.c ==="
awk '/^static int mtk_iommu_of_xlate\(/,/^\}/' $K/drivers/iommu/mtk_iommu_mt6895.c
echo "=== XAGA-MAIN-IOMMU location ==="
grep -rln "XAGA-MAIN-IOMMU" $K/drivers/iommu/ 2>/dev/null
echo "=== which drivers match mt6895-disp-iommu ==="
grep -rn "mt6895-disp-iommu" $K/drivers/iommu/*.c
echo "=== of_match / driver name in mtk_iommu.c ==="
grep -n "static const struct of_device_id mtk_iommu_of_ids\|mtk_iommu_driver = {" -A 25 $K/drivers/iommu/mtk_iommu.c | head -60
echo "=== Module.symvers: mtk iommu entries ==="
grep -i "mtk_iommu" $K/Module.symvers | head
echo "=== check config ==="
zcat ${K50_REPO}/docs/k50_mainline_config.gz | grep -E "MTK_IOMMU|MTK_M4U"
