#!/bin/sh
# zz_cma_remote.sh - device side: is the 32 MiB CMA window readable/writable via /dev/mem?
# READ-ONLY except for three 32-bit writes inside the CMA window, restored afterwards.
echo "=== CMA window probe ==="
date; uptime
echo "--- meminfo ---"
grep -E "CmaTotal|CmaFree|MemFree" /proc/meminfo
echo "--- iomem around CMA ---"
grep -iE "8[0-9a-f]{7}" /proc/iomem | head -20
echo "--- reserved-memory nodes (cma) ---"
for d in /proc/device-tree/reserved-memory/*/; do
  n=$(basename "$d")
  c=$(tr -d '\0' < "$d/compatible" 2>/dev/null)
  echo "  $n compatible=$c"
done 2>/dev/null | head -45
echo "--- rw test at 0x8b000000 (inside CMA) ---"
B=0x8b000000
o1=$(busybox devmem $B 32 2>&1); echo "  orig[0]=$o1"
o2=$(busybox devmem 0x8b000004 32 2>&1); echo "  orig[1]=$o2"
busybox devmem $B 32 0xa5a5c3c3 2>&1
busybox devmem 0x8b000004 32 0x5a5a3c3c 2>&1
r1=$(busybox devmem $B 32 2>&1); echo "  read[0]=$r1"
r2=$(busybox devmem 0x8b000004 32 2>&1); echo "  read[1]=$r2"
echo "  -> writable: $([ "$r1" = "0xA5A5C3C3" ] && echo YES || echo NO)"
echo "--- restore ---"
busybox devmem $B 32 "$o1" 2>&1
busybox devmem 0x8b000004 32 "$o2" 2>&1
echo "  restored[0]=$(busybox devmem $B 32 2>&1)"
echo "--- fb0 geometry ---"
cat /sys/class/graphics/fb0/virtual_size 2>&1
cat /sys/class/graphics/fb0/stride 2>&1
cat /sys/class/graphics/fb0/smem_start 2>&1
cat /sys/class/graphics/fb0/smem_len 2>&1
echo "=== probe done ==="
