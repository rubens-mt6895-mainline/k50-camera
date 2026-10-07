#!/bin/sh
# zz_cap4.sh - load the fixed cam_cap.ko and try a single-frame capture.
# Policy: ONE device-side task, nice -n 19, no background loops.
N="nice -n 19"
echo "=== zz_cap4: cam_cap.ko (cam_route + dma_alloc_coherent) ==="
date; uptime; nproc
echo "--- module table before ---"
grep cam_cap /proc/modules; echo "(empty above = clean)"

echo "--- 1. insmod (dbl_data_bus=1 per camsv_frame_params.md) ---"
insmod /root/cam_cap.ko dbl_data_bus=1
echo "insmod rc=$?"
sleep 0.5
grep cam_cap /proc/modules

if [ ! -f /proc/camcap ]; then
	echo "!!! /proc/camcap missing - module load failed, aborting"
	dmesg | tail -30
	exit 1
fi

echo "--- 2. info after load ---"
cat /proc/camcap_info

echo "--- 3. cfg (4000x3000 RAW10, stride 5000) ---"
echo "cfg 1 0 4000 0 3000 4000 3000 5000" > /proc/camcap
echo "cfg rc=$?"

echo "--- 4. info after cfg ---"
cat /proc/camcap_info

echo "--- 5. route ---"
echo "route" > /proc/camcap
echo "route rc=$?"

echo "--- 6. info after route ---"
cat /proc/camcap_info

echo "--- 7. arm (single frame) ---"
echo "arm" > /proc/camcap
echo "arm rc=$?"

echo "--- 8. info after arm ---"
cat /proc/camcap_info

echo "--- 9. dmesg tail ---"
dmesg | tail -40

echo "--- 10. first 64 bytes of the buffer ---"
$N dd if=/proc/camcap bs=64 count=1 2>/dev/null | od -A x -t x4

echo "--- 11. regs dump ---"
echo "regs" > /proc/camcap
dmesg | tail -45

echo "=== zz_cap4 done ==="
