#!/bin/sh
# Re-test: does clearing SMI_LARB_NONSEC_CON(larb0, port2) F_MMU_EN actually
# bypass IOMMU translation for CAMSV?  Earlier test may have been fooled by
# stale dmesg lines.
echo "=== 0. drain dmesg ==="
dmesg -c >/dev/null 2>&1 || true

echo "=== 1. larb0 SMI_LARB_NONSEC_CON(0..15) @ 0x14021380+4i ==="
i=0
while [ $i -le 15 ]; do
  A=$(printf '0x%x' $((0x14021380 + i*4)))
  V=$(busybox devmem "$A" 32 2>/dev/null)
  echo "  p$i $A = $V"
  i=$((i+1))
done

echo "=== 2. cam_cap state before ==="
cat /proc/camcap_info 2>/dev/null

echo "=== 3. clear F_MMU_EN on port 2 (0x14021388) ==="
busybox devmem 0x14021388 32 0x00000000
echo "  p2 readback = $(busybox devmem 0x14021388 32)"

echo "=== 4. drain dmesg again ==="
dmesg -c >/dev/null 2>&1 || true

echo "=== 5. re-arm CAMSV ==="
echo arm > /proc/camcap
sleep 1
cat /proc/camcap_info 2>/dev/null

echo "=== 6. NEW dmesg since arm ==="
dmesg

echo "=== 7. CAMSV frame seq + int status ==="
echo "  0x75c FRAME_SEQ_NO = $(busybox devmem 0x1a11075c 32)"
echo "  0x04c INT_STATUS   = $(busybox devmem 0x1a11004c 32)"
echo "  0x244 FBC_CTL2     = $(busybox devmem 0x1a110244 32)"

echo "=== 8. buffer first 64 KiB non-zero dword count ==="
dd if=/proc/camcap bs=4096 count=16 2>/dev/null | od -An -tx4 | tr -s ' ' '\n' | grep -v '^$' | grep -vc '^00000000$'
echo "=== 9. first 64 bytes ==="
dd if=/proc/camcap bs=64 count=1 2>/dev/null | od -An -tx4
echo "=== done ==="
