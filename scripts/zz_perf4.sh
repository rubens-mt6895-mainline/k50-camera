#!/bin/sh
# zz_perf4.sh <threads> <frames> - exercise the parallel convert pool.
# Usage on device: sh /root/zz_perf4.sh 2 3
NTH=${1:-2}
NFR=${2:-3}

echo "=== guard (other camera users?) ==="
for p in cheese gst-launch-1.0 ffmpeg; do
	n=$(pgrep -c -x "$p" 2>/dev/null); [ -z "$n" ] && n=0
	echo "  $p: $n"
done
uptime

echo "=== reload conv_threads=$NTH ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>&1
sleep 1
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=$NTH 2>&1
echo "  insmod rc=$?"
sleep 2
echo "  conv_threads=$(cat /sys/module/cam_cap/parameters/conv_threads 2>/dev/null)"

echo "=== stream $NFR frames ==="
timeout 60 nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$NFR --stream-to=/dev/null
echo "  v4l2-ctl rc=$?"

echo "=== worker threads ==="
ps -eLo pid,tid,comm,state,ni 2>/dev/null | grep -E 'cam_conv|COMMAND' | head -12

echo "=== info ==="
grep -E 'convert|timing|stats|ae |awb ' /proc/camcap_info

echo "=== dmesg (crash check) ==="
dmesg | tail -14
echo "--- oops scan ---"
dmesg | grep -E -c 'Oops|paging request|BUG:|Call trace|hung task' || echo "  0 crash lines"
echo "=== load ==="
uptime
