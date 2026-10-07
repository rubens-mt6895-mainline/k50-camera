#!/bin/bash
K=${KDIR}
echo "=== 1. mtk_iommu_get_iova_region_id ==="
sed -n '/static int mtk_iommu_get_iova_region_id/,/^}/p' $K/drivers/iommu/mtk_iommu.c
echo
echo "=== 2. mtk_iommu_get_bank_id ==="
sed -n '/static unsigned int mtk_iommu_get_bank_id/,/^}/p' $K/drivers/iommu/mtk_iommu.c
echo
echo "=== 3. mt8192_larb_region_msk ==="
sed -n '/mt8192_larb_region_msk\[\]/,/};/p' $K/drivers/iommu/mtk_iommu.c
echo
echo "=== 4. MTK_M4U_ID / TO_LARB / TO_PORT macros ==="
grep -n "MTK_M4U_ID\|MTK_M4U_TO_LARB\|MTK_M4U_TO_PORT\|MTK_M4U_TO_TAB\|MTK_M4U_TO_BANK" $K/drivers/iommu/mtk_iommu.c | head -20
echo
echo "=== 5. callers of of_dma_configure_id ==="
grep -rn "of_dma_configure_id\|of_dma_configure(" $K/drivers/base/ $K/drivers/of/ $K/arch/arm64/ 2>/dev/null | grep -v "\.h:" | head -20
echo
echo "=== 6. DMA_OPS config ==="
grep -n "CONFIG_DMA_OPS\|CONFIG_DMA_OPS_BYPASS\|CONFIG_IOMMU_DMA" ${K50_REPO}/docs/k50_mainline_config.gz >/dev/null 2>&1
zcat ${K50_REPO}/docs/k50_mainline_config.gz 2>/dev/null | grep -E "^CONFIG_DMA_OPS|^CONFIG_IOMMU_DMA|^CONFIG_SWIOTLB|^CONFIG_DMA_DIRECT_REMAP" | head
echo
echo "=== 7. of_changeset_create_node signature + of_changeset_apply ==="
sed -n '/struct device_node \*of_changeset_create_node/,/^}/p' $K/drivers/of/dynamic.c | head -30
echo "--- apply ---"
sed -n '/^int of_changeset_apply/,/^}/p' $K/drivers/of/dynamic.c | head -30
echo "--- add_prop_u32_array ---"
sed -n '/^int of_changeset_add_prop_u32_array/,/^}/p' $K/drivers/of/dynamic.c | head -20
echo
echo "=== 8. of_iommu_configure_device + of_iommu_xlate ==="
sed -n '40,100p' $K/drivers/iommu/of_iommu.c
