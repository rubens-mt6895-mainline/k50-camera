#!/bin/sh
# zz_verify.sh - correctness evidence for the parallel converter.
# Captures the SAME fixed settings twice: inline (1) and parallel (4), then
# also one auto-exposure frame to judge the over-exposure fix.
set -u
FIX="-c auto_exposure=1 -c exposure_time_absolute=3072 -c analogue_gain=768 -c digital_gain=1024 -c auto_white_balance=0 -c red_balance=310 -c blue_balance=590"

shot() { # $1 = conv_threads  $2 = output file  $3 = ctl arguments
	pkill -x cheese 2>/dev/null
	sleep 1
	fuser -k /dev/video0 2>/dev/null
	sleep 1
	rmmod cam_cap 2>&1
	sleep 1
	insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=$1 2>&1
	echo "  insmod rc=$? conv_threads=$1"
	sleep 2
	v4l2-ctl -d /dev/video0 $3 >/dev/null 2>&1
	rm -f "$2"
	nice -n 12 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to="$2" >/dev/null 2>&1
	echo "  $2 : $(stat -c %s "$2" 2>/dev/null) bytes"
}

echo "=== fixed settings, inline ==="
shot 1 /root/inl.yuyv "$FIX"
echo "=== fixed settings, 4 threads ==="
shot 4 /root/par.yuyv "$FIX"
echo "=== auto exposure/awb, 4 threads ==="
shot 4 /root/par_auto.yuyv "-c auto_exposure=3 -c auto_white_balance=1"

echo "=== checksums ==="
md5sum /root/inl.yuyv /root/par.yuyv
echo -n "differing bytes (cmp -l | wc -l): "
cmp -l /root/inl.yuyv /root/par.yuyv 2>/dev/null | wc -l

echo "=== info (auto run) ==="
grep -E 'stats|ae |awb |avg' /proc/camcap_info
dmesg | grep -c -E 'Oops|paging request'
