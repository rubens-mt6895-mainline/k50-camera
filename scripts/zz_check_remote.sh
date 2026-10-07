#!/bin/sh
# zz_check_remote.sh - device-side state probe for the camera bring-up.
date; uptime
echo "--- lsmod ---"
lsmod | grep -E "cam_|m6315|ovl" 
echo "--- cam_cap params ---"
for p in frame_bytes use_dma_alloc camsv_base; do
  echo "  $p=$(cat /sys/module/cam_cap/parameters/$p 2>&1)"
done
echo "--- CSI2 port2 counters ---"
printf "  PKT=%s\n" "$(devmem 0x1a014adc 32 2>&1)"
printf "  IRQ=%s\n" "$(devmem 0x1a014ac8 32 2>&1)"
printf "  S0_DI=%s\n" "$(devmem 0x1a014a20 32 2>&1)"
echo "--- dmesg tail ---"
dmesg | grep -iE "cam_cap|CMA|cma" | tail -20
echo "--- done ---"
