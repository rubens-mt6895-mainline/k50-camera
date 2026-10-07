#!/bin/sh
# v78: DMA buffer feasibility probe ? where can CAMSV's IMGO DMA legally write?
# Read-only except nothing. We only inspect memory map + reserved regions.
echo "=== DATE ==="; date; uptime
echo
echo "=== /proc/iomem (System RAM / reserved / cma) ==="
cat /proc/iomem | grep -iE "system ram|reserved|cma|ramoops|mtee|atf|optee|frame|heap" | head -60
echo
echo "=== meminfo ==="
grep -iE "MemTotal|CmaTotal|CmaFree|MemAvailable" /proc/meminfo
echo
echo "=== cmdline ==="
cat /proc/cmdline
echo
echo "=== CMA debugfs ==="
ls -l /sys/kernel/debug/cma 2>&1 | head -20
echo
echo "=== reserved-memory in live DT ==="
ls /proc/device-tree/reserved-memory/ 2>&1 | head -40
echo
echo "=== dmesg: cma / reserved / dma ==="
dmesg | grep -iE "cma|reserved memory|dma_alloc|iommu" | tail -30
echo
echo "=== iommu present? ==="
ls /sys/class/iommu 2>&1
echo "--- mtk iommu dmesg ---"
dmesg | grep -iE "mtk-iommu|iommu.*probe|IOMMU" | tail -20
echo
echo "=== is /dev/mem present + writable open test ==="
ls -l /dev/mem
echo
echo "=== page count / RAM top ==="
head -1 /proc/iomem
grep -c . /proc/iomem
echo
echo "=== seninf/camsv iomem claims ==="
grep -iE "1a0|1a1|11c8" /proc/iomem | head -30
echo
echo "=== modules ==="
lsmod
echo
echo "=== DONE v78 ==="

