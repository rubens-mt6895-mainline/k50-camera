#!/bin/sh
# zz_perf3.sh - step 1: inline converter (conv_threads=1) must behave exactly as before.
set -u

echo "=== guard ==="
for p in cheese gst-launch-1.0 ffmpeg; do
	n=$(pgrep -c -x "$p" 2>/dev/null); [ -z "$n" ] && n=0
	echo "  $p: $n"
done

echo "=== reload inline (conv_threads=1) ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>&1
sleep 1
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=1 2>&1
echo "  insmod rc=$?"
sleep 2
echo "  conv_threads=$(cat /sys/module/cam_cap/parameters/conv_threads)"
echo "  route_once=$(cat /sys/module/cam_cap/parameters/route_once) gain_q8=$(cat /sys/module/cam_cap/parameters/v4l2_gain_q8) ae_target=$(cat /sys/module/cam_cap/parameters/ae_target)"

echo "=== stream 5 frames (inline) ==="
nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=5 --stream-to=/dev/null
echo "  v4l2-ctl rc=$?"

echo "=== timing ==="
grep -E 'convert|timing' /proc/camcap_info
grep -E 'stats|ae |awb ' /proc/camcap_info

echo "=== dmesg tail ==="
dmesg | tail -6
echo "=== load ==="
uptime
