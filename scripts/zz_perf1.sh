#!/bin/sh
# zz_perf1.sh - measure the V4L2 frame rate with the parallel converter.
#
# Device side.  One device task at a time: the only load this creates is one
# v4l2-ctl stream of 60 frames plus a few /proc reads.
#
# The interesting numbers come straight out of /proc/camcap_info:
#   convert : parallel/inline and how many threads
#   timing  : period / arm / conv / gov / idle in microseconds + measured fps
set -u

CONV="${1:-0}"
echo "conv_threads=$CONV"

echo "=== uptime / load before ==="
uptime 2>/dev/null

echo "=== stop anything using the camera ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

echo "=== reload cam_cap ==="
rmmod cam_cap 2>&1
sleep 1
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads="$CONV" 2>&1
echo "insmod rc=$?"
sleep 2

echo "=== params ==="
for p in v4l2_enable conv_threads route_once single_mode pak_mode pak_dbl \
	 dbl_data_bus route_pix_mode frame_bytes ae_enable ae_target awb_enable; do
	printf '%-16s %s\n' "$p" "$(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)"
done

echo "=== before streaming ==="
grep -E 'convert|timing' /proc/camcap_info

echo "=== stream 60 frames in the background ==="
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=60 --stream-to=/dev/null \
	>/tmp/stream.log 2>&1 &
SPID=$!

i=1
while [ $i -le 8 ]; do
	sleep 2
	if ! kill -0 $SPID 2>/dev/null; then
		echo "--- stream finished before sample $i ---"
		break
	fi
	echo "--- sample $i (load: $(cut -d' ' -f1-3 /proc/loadavg)) ---"
	grep -E 'stats|ae |awb |convert|timing' /proc/camcap_info
	i=$((i + 1))
done

wait $SPID
echo "=== stream log ==="
cat /tmp/stream.log

echo "=== after streaming ==="
grep -E 'convert|timing' /proc/camcap_info

echo "=== arm trace (2 frames only) ==="
echo 1 > /sys/module/cam_cap/parameters/arm_trace
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=2 --stream-to=/dev/null >/dev/null 2>&1
echo 0 > /sys/module/cam_cap/parameters/arm_trace
dmesg | grep -E 'cam_cap: (arm|route)' | tail -8

echo "=== load after ==="
uptime 2>/dev/null
dmesg | grep -E 'convert:|v4l2: streaming' | tail -4
