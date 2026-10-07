#!/bin/sh
# zz_cap3.sh - device side: load the CMA-based cam_cap.ko and smoke test it.
echo "=== cam_cap load (CMA path) ==="
date; uptime
echo "--- sensor / CSI2 state BEFORE ---"
printf "  PKT=%s\n" "$(busybox devmem 0x1a014adc 32 2>&1)"
printf "  IRQ=%s\n" "$(busybox devmem 0x1a014ac8 32 2>&1)"
printf "  S0_DI=%s\n" "$(busybox devmem 0x1a014a20 32 2>&1)"
echo "--- MemInfo CMA ---"
grep -E "CmaTotal|CmaFree|MemFree" /proc/meminfo

echo "--- stale module state ---"
grep cam_cap /proc/modules 2>&1
rmmod cam_cap 2>&1; echo "  rmmod rc=$?"
grep cam_cap /proc/modules 2>&1

sleep 0.2
insmod /root/cam_cap.ko dbl_data_bus=1
echo "insmod rc=$?"
lsmod | grep cam_cap

echo "--- module params ---"
for p in frame_bytes use_dma_alloc camsv_base route_en; do
  echo "  $p=$(cat /sys/module/cam_cap/parameters/$p 2>&1)"
done

echo "--- /proc/camcap_info (before cfg) ---"
cat /proc/camcap_info 2>&1

echo "--- cfg: RAW10 4000x3000 packed 5000 B/line ---"
echo 'cfg 1 0 4000 0 3000 5000 3000 5000' > /proc/camcap
echo "  cfg rc=$?"

echo "--- regs dump ---"
echo 'regs' > /proc/camcap

echo "--- /proc/camcap_info (after cfg) ---"
cat /proc/camcap_info 2>&1

echo "--- dmesg tail ---"
dmesg | tail -40
echo "=== zz_cap3 done (module left loaded) ==="
