#!/bin/bash
K=${KDIR}
echo "=== 1. mtk_sip_svc.h ==="
cat $K/include/linux/soc/mediatek/mtk_sip_svc.h
echo
echo "=== 2. include/soc/mediatek/smi.h ==="
cat $K/include/soc/mediatek/smi.h
echo
echo "=== 3. mt6895 larb_gen flags ==="
sed -n '720,760p' $K/drivers/memory/mtk-smi.c
echo
echo "=== 4. MTK_SMI_FLAG_CFG_PORT_SEC_CTL defs ==="
grep -rn "CFG_PORT_SEC_CTL" $K/drivers/memory/mtk-smi.c $K/include/soc/mediatek/smi.h | head
echo
echo "=== 5. of_platform_device_create_pdata ==="
sed -n '/of_platform_device_create_pdata(/,/^}/p' $K/drivers/of/platform.c | head -50
echo
echo "=== 6. of_dma_configure -> of_iommu_configure ==="
grep -n "of_iommu_configure\|of_dma_configure_id\|of_dma_configure(" $K/drivers/of/device.c $K/drivers/of/platform.c $K/drivers/iommu/of_iommu.c | head -20
echo
echo "=== 7. mtk_iommu_mt6895.c 355,390 ==="
sed -n '355,390p' $K/drivers/iommu/mtk_iommu_mt6895.c
echo
echo "=== 8. mtk_iommu_mt6895.c 455,480 ==="
sed -n '455,480p' $K/drivers/iommu/mtk_iommu_mt6895.c
echo
echo "=== 9. mtk_iommu.c 665,690 ==="
sed -n '665,690p' $K/drivers/iommu/mtk_iommu.c
