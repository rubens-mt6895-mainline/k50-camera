#!/bin/bash
K=${KDIR}
echo "=== 1. SIP / ATF constants ==="
grep -rn "MTK_SIP_KERNEL_IOMMU_CONTROL" $K/include/ $K/drivers/ 2>/dev/null | head -10
grep -rn "IOMMU_ATF_CMD_CONFIG_SMI_LARB" $K/include/ $K/drivers/ 2>/dev/null | head -10
echo
echo "=== 2. arm_smccc exports ==="
grep -E "__arm_smccc_smc|__arm_smccc_hvc" $K/Module.symvers | head
echo
echo "=== 3. of_* exports ==="
grep -E "	of_platform_device_create|	of_platform_default_populate|	of_find_device_by_node|	of_find_compatible_node|	of_overlay_fdt_apply|	of_node_put|	of_platform_device_destroy" $K/Module.symvers | head -20
echo
echo "=== 4. iommu exports (all) ==="
grep -E "	iommu_" $K/Module.symvers | head -40
echo
echo "=== 5. of_platform_notify present? ==="
grep -n "of_platform_notify\|of_reconfig_notifier_register" $K/drivers/of/platform.c | head
echo
echo "=== 6. mtk-smi larb_gen for mt6895: which mmu-en path ==="
grep -n "mt6895\|smi_plat_data\b" $K/drivers/memory/mtk-smi.c | head -30
echo
echo "=== 7. mtk-smi.c 165,210 (larb iommu init) ==="
sed -n '165,215p' $K/drivers/memory/mtk-smi.c
echo
echo "=== 8. mtk-smi.c 330,365 (mmu_en set path) ==="
sed -n '330,365p' $K/drivers/memory/mtk-smi.c
