#!/bin/bash
K=${KDIR}
echo "--- mtk_iommu_ops definition ---"
sed -n '/^static const struct iommu_ops mtk_iommu_ops/,/^};/p' $K/drivers/iommu/mtk_iommu.c
echo "--- any of_xlate in mtk_iommu.c ---"
grep -n "of_xlate" $K/drivers/iommu/mtk_iommu.c
echo "--- iommu_fwspec_init signature/proto ---"
grep -rn "iommu_fwspec_init" $K/include/linux/iommu.h $K/drivers/iommu/iommu.c | head
echo "--- iommu_fwspec_init body ---"
sed -n '/^int iommu_fwspec_init(/,/^}/p' $K/drivers/iommu/iommu.c
echo "--- iommu_ops_from_fwnode ---"
sed -n '/struct iommu_ops \*iommu_ops_from_fwnode/,/^}/p' $K/drivers/iommu/iommu.c | head -30
echo "--- iommu-priv.h iommu_fwspec_init ---"
grep -n "iommu_fwspec_init" $K/drivers/iommu/iommu-priv.h
echo "--- all iommu_ops with of_xlate in tree ---"
grep -rln "of_xlate" $K/drivers/iommu/*.c | head -20
echo "--- mtk_iommu_of_xlate? ---"
grep -rn "mtk_iommu_of_xlate\|of_xlate" $K/drivers/iommu/mtk_iommu.c $K/drivers/iommu/mtk_iommu_v1.c 2>/dev/null | head
