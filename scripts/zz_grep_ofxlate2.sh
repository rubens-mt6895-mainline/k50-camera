#!/bin/bash
K=${KDIR}
echo "--- mtk_iommu_ops = { ... } ---"
grep -n "mtk_iommu_ops = {" $K/drivers/iommu/mtk_iommu.c
awk '/mtk_iommu_ops = \{/,/^\};/' $K/drivers/iommu/mtk_iommu.c
echo "--- of_xlate anywhere in mtk_iommu.c ---"
grep -n "of_xlate" $K/drivers/iommu/mtk_iommu.c
echo "--- iommu_fwspec_init proto ---"
grep -rn "iommu_fwspec_init" $K/include/linux/iommu.h
echo "--- iommu_fwspec_init body ---"
awk '/^int iommu_fwspec_init\(/,/^\}/' $K/drivers/iommu/iommu.c
echo "--- iommu_ops_from_fwnode ---"
awk '/iommu_ops_from_fwnode\(const struct fwnode_handle/,/^\}/' $K/drivers/iommu/iommu.c
echo "--- which ops in tree define of_xlate ---"
grep -rn "\.of_xlate" $K/drivers/iommu/ 2>/dev/null
echo "--- of_xlate in iommu.h ---"
grep -n "of_xlate" $K/include/linux/iommu.h
