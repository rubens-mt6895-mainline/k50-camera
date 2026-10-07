#!/bin/sh
# zz_armdiag.sh - bare-arm ceiling and DMA-progress probe.
#
# Two questions, both decided by the new proc commands:
#   burst N  arms N frames back to back with no conversion and no statistics,
#            so it reports the sensor/CAMSV ceiling on its own.
#   probe    arms one frame with a 1 ms register trace, so the log shows when
#            the frame start (INT_VS_ST) lands and whether FBC_IMGO_CTL2 counts
#            the DMA progress down the frame.
set -u

echo "=== stop any consumer ==="
pkill -x cheese 2>/dev/null
sleep 0.3
fuser -k /dev/video0 2>/dev/null
sleep 0.3

echo "=== reload cam_cap ==="
rmmod cam_cap 2>/dev/null
insmod /root/cam_cap.ko v4l2_enable=1
sleep 0.5

echo "=== buffer state ==="
grep -E 'buffer_|mapping|iommu|iova' /proc/camcap_info

# clear the ring so what is left below is only this run's diagnostics
dmesg -c >/dev/null 2>&1

echo "=== route + cfg ==="
echo route > /proc/camcap
echo "cfg 1 0 4000 0 3000 6000 3000 6000" > /proc/camcap
sleep 0.2

echo "=== burst 16 (arm only, no conversion) ==="
echo burst 16 > /proc/camcap
echo "burst rc=$?"

echo "=== burst 16 (steady state again) ==="
echo burst 16 > /proc/camcap
echo "burst rc=$?"

echo "=== probe (1 ms register trace) ==="
echo probe > /proc/camcap
echo "probe rc=$?"

echo "=== /proc/camcap_info after ==="
head -30 /proc/camcap_info

echo "=== dmesg (burst/probe) ==="
dmesg | grep -E 'burst|probe'

echo "=== crash scan (expect 0) ==="
dmesg | grep -cE 'Oops|paging request|BUG:'

echo "=== load ==="
cat /proc/loadavg
