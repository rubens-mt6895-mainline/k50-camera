#!/bin/bash
K=${KDIR}
echo "=== iommu_dma_alloc ==="
awk '/^static void \*iommu_dma_alloc\(/,/^\}/' $K/drivers/iommu/dma-iommu.c
echo "=== __iommu_dma_alloc ==="
awk '/^static struct page \*__iommu_dma_alloc\(/,/^\}/' $K/drivers/iommu/dma-iommu.c
echo "=== iommu_dma_alloc_noncontiguous ==="
awk '/^static void \*iommu_dma_alloc_noncontiguous\(/,/^\}/' $K/drivers/iommu/dma-iommu.c
echo "=== v7s line 405-425 ==="
sed -n '400,425p' $K/drivers/iommu/io-pgtable-arm-v7s.c
echo "=== iommu_dma_alloc_pages head ==="
awk '/^static struct page \*\*iommu_dma_alloc_pages\(/,/^\}/' $K/drivers/iommu/dma-iommu.c | head -60
