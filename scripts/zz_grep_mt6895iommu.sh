#!/bin/bash
K=${KDIR}
M=$K/drivers/iommu/mtk_iommu_mt6895.c
echo "=== Makefile iommu mtk ==="
grep -n "mtk_iommu" $K/drivers/iommu/Makefile
echo "=== XAGA in both files ==="
grep -c "XAGA" $M $K/drivers/iommu/mtk_iommu.c
echo "=== mt6895 file: ops struct (2030-2080) ==="
sed -n '2030,2080p' $M
echo "=== mt6895 of_xlate full ==="
sed -n '/static int mtk_iommu_of_xlate/,/^}/p' $M
echo "=== mt6895 probe_device ==="
sed -n '/^static int mtk_iommu_probe_device/,/^}/p' $M
echo "=== mt6895 attach_device ==="
sed -n '/^static int mtk_iommu_attach_device/,/^}/p' $M
echo "=== mt6895 hw_init (head) ==="
sed -n '/^static int mtk_iommu_hw_init/,/^}/p' $M | head -60
echo "=== mt6895 driver of_match / name ==="
sed -n '3670,3700p' $M
