#!/bin/bash
K=${KDIR}
echo "=== 1. mtk_iommu.c : fault reporting ==="
grep -n "fault type=\|larb=\|int_id\|mtk_iommu_get_fault_id\|F_MMU_INT\|larbid\|port=" $K/drivers/iommu/mtk_iommu.c | head -50
echo
echo "=== 2. mtk_iommu.c : hw_init / PT base / sec ==="
grep -n "MMU_PT_BASE\|mtk_iommu_hw_init\|MTK-IOMMU-SEC\|sec_id\|IOMMU_ATF\|mtk_iommu_sec\|no_hw_support" $K/drivers/iommu/mtk_iommu.c | head -50
echo
echo "=== 3. mtk_iommu.c : probe_device / add_device / setup_dma_ops ==="
grep -n "probe_device\|add_device\|iommu_setup_dma_ops\|iommu_device_register\|of_iommu\|const struct iommu_ops\|mtk_iommu_ops\|iommu_domain_alloc" $K/drivers/iommu/mtk_iommu.c | head -40
echo
echo "=== 4. disp_iommu node ==="
awk '/disp_iommu: iommu@1e802000/,/^\t\t};/' $K/arch/arm64/boot/dts/mediatek/mt6895.dtsi | head -40
echo
echo "=== 5. config: IOMMU ==="
zcat ${K50_REPO}/docs/k50_mainline_config.gz 2>/dev/null | grep -E "CONFIG_IOMMU|CONFIG_MTK_IOMMU|CONFIG_ARM_SMMU|CONFIG_OF_IOMMU|CONFIG_IOMMU_DMA|CONFIG_IOMMU_SUPPORT" | head -30
echo
echo "=== 6. Module.symvers IOMMU exports ==="
grep -E "iommu_probe_device|iommu_attach_device|iommu_domain_alloc|iommu_map\b|iommu_setup_dma_ops|iommu_get_domain_for_dev|iommu_dev_enable_feature|dev_iommu_fwspec" $K/Module.symvers | head -30
echo
echo "=== 7. mt6895 iommu match data (sec / bank) ==="
grep -n "mt6895" $K/drivers/iommu/mtk_iommu.c | head -30
