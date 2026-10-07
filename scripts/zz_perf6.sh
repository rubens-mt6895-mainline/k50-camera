#!/bin/sh
# zz_perf6.sh <threads> <frames> - reload with the cacheable-alias build and
# measure one convert-pool point, then save a few frames for a visual check.
# Device side.  One device task at a time: nothing here runs in the background.
NTH=${1:-4}
NFR=${2:-24}
set -u

echo "=== stop anything using the camera ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
echo "cheese left: $(pgrep -c -x cheese 2>/dev/null || echo 0)"

echo "=== reload ==="
rmmod cam_cap 2>&1
sleep 1
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=$NTH 2>&1
echo "insmod rc=$? conv_threads=$NTH"
sleep 2

echo "=== how the frame buffer is read ==="
dmesg | grep -E 'cam_cap: buffer|forcing|convert:' | tail -8
echo

echo "=== $NFR frames through v4l2-ctl ==="
timeout 180 nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$NFR \
	--stream-to=/dev/null 2>&1 | tail -2
echo "v4l2-ctl rc=$?"
echo

echo "=== /proc/camcap_info (timing + stats) ==="
grep -E 'avg|last|stats|convert|buffer' /proc/camcap_info
echo

echo "=== 4 frames to /root/fast.yuyv ==="
timeout 120 nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=4 \
	--stream-to=/root/fast.yuyv 2>&1 | tail -1
ls -l /root/fast.yuyv 2>&1
echo

echo "=== crash scan ==="
echo -n "crash lines this boot: "
dmesg | grep -c -E 'Oops|paging request|BUG: unable'
dmesg | grep -E 'cam_cap: (convert|v4l2)' | tail -3
uptime
