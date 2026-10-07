#!/bin/sh
# zz_rate.sh - steady-state fps and AE/AWB state, no module reload (the module is
# already loaded and streaming works).  Runs the same 100-frame stream with
# different convert thread counts so the "arm misses a period when the converter
# is still busy" hypothesis can be checked.
set -u
P=/sys/module/cam_cap/parameters

pkill -x cheese 2>/dev/null
sleep 0.5
fuser -k /dev/video0 2>/dev/null
sleep 0.5

echo "=== module state ==="
grep -E 'cam_cap|videobuf|videodev' /proc/modules
echo "conv_threads = $(cat $P/conv_threads)  pipeline = $(cat $P/pipeline)  rb_swap = $(cat $P/rb_swap)"

run() {
	echo "$1" > "$P/conv_threads"
	echo
	echo "=== conv_threads=$1 : 100 frames ==="
	nice -n 10 timeout 180 v4l2-ctl -d /dev/video0 --stream-mmap \
		--stream-count=100 --stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -2
	grep -E '^(avg|stats|wb)' /proc/camcap_info 2>/dev/null | head -6
	sleep 0.5
	dmesg | grep 'convert:' | tail -1
}

run 4
run 8
run 4

echo
echo "=== settle + keep one ordinary frame ==="
nice -n 10 timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=3 \
	--stream-to=/root/rate_settled.yuyv >/dev/null 2>&1
tail -c 6000000 /root/rate_settled.yuyv > /root/rate_settled1.yuyv
ls -l /root/rate_settled1.yuyv
grep -E '^(avg|stats|wb)' /proc/camcap_info 2>/dev/null | head -6

echo
echo "=== crash scan (should be 0) ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace' || true
echo "=== loadavg ==="
cat /proc/loadavg
