#!/bin/bash
K=${KDIR}
echo "=== 1. of_changeset / dynamic node exports ==="
grep -E "	of_changeset" $K/Module.symvers | head -20
echo "--- (none above means not exported) ---"
echo
echo "=== 2. of_ helpers exports ==="
grep -E "	of_(get_parent|find_node_by_path|find_node_by_name|device_is_available|node_get|node_put|add_property|remove_property|dma_configure|node_alloc|node_free|attach_node_and_children|detach_node_and_children|parse_phandle_with_args|device_add)" $K/Module.symvers | head -20
echo
echo "=== 3. of_dma_configure definition ==="
grep -n "of_dma_configure" $K/include/linux/of_device.h $K/include/linux/of.h 2>/dev/null | head
echo
echo "=== 4. of_iommu.c 100,175 ==="
sed -n '100,175p' $K/drivers/iommu/of_iommu.c
echo
echo "=== 5. io-pgtable-arm-v7s.c MTK_EXT pte ==="
grep -n "MTK_EXT\|MTK_TTBR_EXT\|arm_v7s_prot_to_pte\|__arm_v7s_pte_pa\|ARM_V7S_ATTR_SECTION\|LVL_MASK" $K/drivers/iommu/io-pgtable-arm-v7s.c | head -40
echo
echo "=== 6. io-pgtable-arm-v7s.c 90,190 ==="
sed -n '90,190p' $K/drivers/iommu/io-pgtable-arm-v7s.c
