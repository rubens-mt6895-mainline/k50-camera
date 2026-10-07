#!/bin/sh
# zz_larb_clear.sh - clear SMI larb0 port2 MMU_EN so CAMSV IMGO writes bypass the IOMMU,
# then re-arm and see whether the frame lands.
# SMI_LARB_NONSEC_CON(2) on larb0 @0x14021000 = 0x14021000 + 0x380 + 2*4 = 0x14021388
N="nice -n 19"
REG=0x14021388
echo "=== zz_larb_clear @ $(date) ==="
uptime

echo "--- 1. stop CAMSV ---"
echo "stop" > /proc/camcap

echo "--- 2. read the SMI port register ---"
BEFORE=$(busybox devmem $REG 32)
echo "  $REG = $BEFORE"

echo "--- 3. clear bit0 (F_MMU_EN) ---"
busybox devmem $REG 32 0x00000000
AFTER=$(busybox devmem $REG 32)
echo "  $REG = $AFTER (was $BEFORE)"

echo "--- 4. re-arm ---"
dmesg -c > /dev/null 2>&1
echo "arm" > /proc/camcap
sleep 1

echo "--- 5. dmesg after arm ---"
dmesg | grep -E "cam_cap|mtk-iommu|mtk_iommu" | tail -20

echo "--- 6. info ---"
cat /proc/camcap_info

echo "--- 7. first 64 bytes of the frame buffer ---"
$N dd if=/proc/camcap bs=64 count=1 2>/dev/null | od -A x -t x4

echo "--- 8. is it still all zero? count non-zero words in the first 1 MiB ---"
$N dd if=/proc/camcap bs=4096 count=256 2>/dev/null | od -A n -t x4 -v | tr -s " " "\n" | grep -vc "^0*$"

echo "=== zz_larb_clear done ==="
