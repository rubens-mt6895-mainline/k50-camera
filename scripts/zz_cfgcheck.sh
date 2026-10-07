#!/bin/bash
K=${KDIR}
echo "=== tree .config OF/IOMMU ==="
grep -E "^CONFIG_OF_DYNAMIC|^CONFIG_OF_OVERLAY|^CONFIG_OF=|^CONFIG_OF_IOMMU|^CONFIG_IOMMU_API|^CONFIG_IOMMU_DMA|^CONFIG_IOMMU_SUPPORT|^CONFIG_DMA_OPS|^CONFIG_ARCH_FORCE_MAX_ORDER|^CONFIG_CMA=" $K/.config
echo "=== struct of_changeset ==="
sed -n '1668,1690p' $K/include/linux/of.h
echo "=== of_changeset_add_prop_string proto ==="
sed -n '1729,1750p' $K/include/linux/of.h
echo "=== build tree vermagic/flags ==="
grep -E "^CONFIG_CC_IS|^CONFIG_LOCALVERSION|^CONFIG_PM_GENERIC_DOMAINS" $K/.config
