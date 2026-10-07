#!/bin/bash
K=${KDIR}
echo "=== A. mtk_iommu.c 1172-1275 (hw_init) ==="
sed -n '1172,1275p' $K/drivers/iommu/mtk_iommu.c
echo
echo "=== B. mtk_iommu.c 1660,1700 (attach -> ttbr) ==="
sed -n '1655,1705p' $K/drivers/iommu/mtk_iommu.c
echo
echo "=== C. mtk_iommu.c 1755,1815 (mt6895 plat data) ==="
sed -n '1755,1815p' $K/drivers/iommu/mtk_iommu.c
echo
echo "=== D. mtk_iommu.c : io_pgtable cfg ==="
grep -n "io_pgtable_cfg\|IO_PGTABLE_QUIRK\|pgsize_bitmap\|arm_v7s_cfg\|cfg = " $K/drivers/iommu/mtk_iommu.c | head -30
echo
echo "=== E. mtk_iommu.c 740,870 (domain alloc + hw init call) ==="
sed -n '740,860p' $K/drivers/iommu/mtk_iommu.c
