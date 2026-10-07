#!/bin/bash
K=${KDIR}
echo "=== of_dma_configure_id body ==="
awk '/^int of_dma_configure_id\(/,/^\}/' $K/drivers/of/device.c
echo "=== of_dma_configure inline ==="
grep -n "of_dma_configure" -A 8 $K/include/linux/of_device.h | head -40
echo "=== of_platform_device_create_pdata ==="
awk '/^static struct platform_device \*of_platform_device_create_pdata/,/^\}/' $K/drivers/of/platform.c
echo "=== of_platform_device_create ==="
awk '/^struct platform_device \*of_platform_device_create\(/,/^\}/' $K/drivers/of/platform.c
echo "=== M4U_TO_DOM/TAB ==="
grep -rn "MTK_M4U_TO_DOM\|MTK_M4U_TO_TAB\|MTK_M4U_TO_BANK" $K/drivers/iommu/mtk_iommu_mt6895.c | head -5
echo "=== mt6895_multi_dom_mm ==="
awk '/mt6895_multi_dom_mm\[\]/,/^\};/' $K/drivers/iommu/mtk_iommu_mt6895.c | head -30
echo "=== mtk_iommu_set_dev_dma ==="
awk '/^static void mtk_iommu_set_dev_dma/,/^\}/' $K/drivers/iommu/mtk_iommu_mt6895.c
echo "=== mtk_iommu_config (head 40) ==="
awk '/^static void mtk_iommu_config\(/,/^\}/' $K/drivers/iommu/mtk_iommu_mt6895.c | head -50
