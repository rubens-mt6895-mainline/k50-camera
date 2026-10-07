#!/bin/sh
# zz_reload30.sh - load the final cam_cap (histogram placement fix) on top of the
# running bring-up and confirm the rate and the dist line.
set -u

pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

echo "=== reload the module (keeps the VTS 3300 bring-up) ==="
sh /root/zz_cam_up.sh 2>&1 | grep -E '\[ok\]|\[!!\]|name:' | tail -5
echo "  exp_max = $(cat /sys/module/cam_cap/parameters/exp_max 2>/dev/null)  conv_threads = $(cat /sys/module/cam_cap/parameters/conv_threads)"

echo
echo "=== 100 frames ==="
nice -n 10 timeout 120 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=100 \
	--stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1
grep -E '^(timing|avg|dist|ae|stats)' /proc/camcap_info | head -5

echo
echo "=== crash scan (want 0) + load ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace'
cat /proc/loadavg
