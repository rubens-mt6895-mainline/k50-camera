#!/bin/sh
# zz_final30.sh - cold start with the new VTS and a long steady measurement at
# three converter thread counts, plus the frame-period histogram.
set -u

pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap || { echo "ABORT: rmmod failed"; exit 1; }
	echo "cam_cap removed"
fi

echo "=== bring-up (VTS 3300) ==="
sh /root/zz_v80.sh 2>&1 | tail -12

rd2() { i2ctransfer -y -f 10 w2@0x10 "$1" "$2" r2@0x10 2>&1; }
echo "  VTS (0x0340) = $(rd2 0x03 0x40)   HTS = $(rd2 0x03 0x42)"

echo
echo "=== stack ==="
sh /root/zz_cam_up.sh 2>&1 | grep -E '\[ok\]|\[!!\]|name:' | tail -8
echo "  exp_max = $(cat /sys/module/cam_cap/parameters/exp_max 2>/dev/null)"
echo "  rb_swap = $(cat /sys/module/cam_cap/parameters/rb_swap 2>/dev/null)"

echo
echo "=== settle 4 s, then 200 frames at 4 / 6 / 8 threads ==="
sleep 4
for n in 4 6 8; do
	echo "$n" > /sys/module/cam_cap/parameters/conv_threads
	sleep 2
	r=$(nice -n 10 timeout 180 v4l2-ctl -d /dev/video0 --stream-mmap \
		--stream-count=200 --stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1)
	echo "--- conv_threads=$n : $r"
	grep -E '^(avg|dist|ae|stats)' /proc/camcap_info | head -4
done

echo
echo "=== keep one settled frame ==="
nice -n 10 timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=3 \
	--stream-to=/root/final.yuyv >/dev/null 2>&1
tail -c 6000000 /root/final.yuyv > /root/final1.yuyv
ls -l /root/final1.yuyv

echo
echo "=== crash scan (want 0) + load ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace'
cat /proc/loadavg
