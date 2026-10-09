#!/bin/sh
# Verify the code-review fixes on the device: stop anything holding the node,
# unload, load the pushed /root/cam_cap.ko on the default preview stack, stream
# 100 frames, and report the rate, the period buckets, AE/AWB/AF state, the
# converter pool size and the crash count.
set -u

echo "=== when ==="
date
uptime

echo "=== holders ==="
pkill -x cheese 2>/dev/null && echo "stopped cheese" || echo "cheese not running"
sleep 1

echo "=== before ==="
lsmod | grep -E 'cam_cap|cam_ovl' || echo "(cam_cap not loaded)"
md5sum /root/cam_cap.ko

echo "=== unload ==="
if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap && echo "rmmod ok" || echo "rmmod FAILED"
fi
if grep -q '^cam_cap ' /proc/modules; then
	echo "ABORT: cam_cap still loaded"
	exit 1
fi

echo "=== bring-up (rails, then camera; same order as cam_boot.sh) ==="
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh 2>&1 | tail -3
sh /root/zz_cam_up.sh 2>&1 | tail -6

echo "=== load lines ==="
dmesg | grep -E 'cam_cap: (source|output|v4l2: registered|growing|loaded|mode:)' | tail -10
echo "=== pool lines ==="
dmesg | grep -iE 'cam_cap:.*(convert|worker|single threaded)' | tail -3

echo "=== stream: 100 frames ==="
timeout 30 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=100 --stream-to=/dev/null 2>&1 | tail -3

echo "=== info ==="
grep -E '^(avg|timing|dist|ae|awb|af|stats)' /proc/camcap_info | head -12

echo "=== arm timeouts in dmesg (all time) ==="
dmesg | grep -c 'timed out'
echo "=== crashes ==="
dmesg | grep -icE 'Oops|BUG:|panic|segfault|Unable to handle|Internal error|Call trace'
echo "=== stray processes ==="
ps -eo pid,comm,args | grep -E 'v4l2-ctl|cheese' | grep -v grep || echo "(none)"
echo "=== done ==="
