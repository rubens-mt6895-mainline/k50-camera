#!/bin/sh
# v79: decide WHERE the CAMSV IMGO DMA buffer can live.
# (a) can /dev/mem touch RAM at all?  (b) list reserved-memory blocks and sizes.
echo "=== DATE ==="; date; uptime
echo
echo "=== /dev/mem RAM read test (reads only) ==="
for a in 0x8a000000 0xd4000000 0x70000000 0xbf900000 0x8e500000 0xbd000000; do
  r=$(busybox devmem $a 32 2>&1)
  echo "read $a -> $r"
done
echo
echo "=== /sys/kernel/debug top ==="
ls /sys/kernel/debug 2>&1 | head -40
echo
echo "=== dma heap / udmabuf / dma devices ==="
ls -l /dev/dma_heap 2>&1
ls -l /dev/udmabuf 2>&1
ls /dev/dma* 2>&1
echo
echo "=== reserved-memory blocks: size (bytes) ==="
cd /proc/device-tree/reserved-memory 2>/dev/null || { echo "no reserved-memory node"; exit 0; }
for d in */; do
  n="${d%/}"
  regf="$n/reg"
  [ -f "$regf" ] || continue
  # reg = <addr_hi addr_lo size_hi size_lo> as big-endian u32
  set -- $(od -An -tx4 -N16 "$regf")
  sz=$(( (0x$3 << 32) + 0x$4 ))
  ad=$(( (0x$1 << 32) + 0x$2 ))
  if [ "$sz" -ge 8388608 ]; then
    printf "%-45s addr=0x%x size=%d (0x%x) MB=%d\n" "$n" "$ad" "$sz" "$sz" $((sz/1048576))
  fi
done
echo
echo "=== framebuffer phys/size ==="
cat /sys/class/graphics/fb0/virtual_size 2>&1
cat /sys/class/graphics/fb0/size 2>&1
ls /sys/class/graphics/ 2>&1
echo
echo "=== DONE v79 ==="
