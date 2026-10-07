#!/bin/sh
# zz_perf2.sh - gentle frame-rate measurement with the fixed parallel converter.
#
# Deliberately conservative after the 21:44 hang:
#   * conv_threads=2 (not the 8-way auto default)
#   * short stream (15 frames), the consumer runs at nice 10
#   * the sampling loop prints every 2 s so the ssh session never goes quiet
set -u

CONV=2
KO=/root/cam_cap.ko

echo "=== guard ==="
for p in cheese gst-launch-1.0 ffmpeg; do
	n=$(pgrep -c -x "$p" 2>/dev/null); [ -z "$n" ] && n=0
	echo "  $p: $n"
done

echo "=== reload with conv_threads=$CONV ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>&1
sleep 1
insmod "$KO" v4l2_enable=1 conv_threads=$CONV 2>&1
echo "  insmod rc=$?"
sleep 2

echo "=== params ==="
for p in v4l2_enable conv_threads route_once v4l2_gain_q8 ae_target ae_band \
	 v4l2_black out_width out_height; do
	printf '  %-16s %s\n' "$p" "$(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)"
done

echo "=== before streaming ==="
grep -E 'convert|timing' /proc/camcap_info

echo "=== stream 15 frames (consumer at nice 10) ==="
nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=15 \
	--stream-to=/dev/null >/tmp/s.log 2>&1 &
SPID=$!
i=1
while [ $i -le 12 ]; do
	sleep 2
	if ! kill -0 $SPID 2>/dev/null; then
		echo "  [stream ended before sample $i]"
		break
	fi
	echo "  --- sample $i (load: $(cut -d' ' -f1-3 /proc/loadavg)) ---"
	grep -E 'convert|timing' /proc/camcap_info
	i=$((i + 1))
done
wait $SPID
echo "  stream rc=$?"
cat /tmp/s.log

echo "=== after streaming ==="
grep -E 'convert|timing|stats|ae |awb ' /proc/camcap_info

echo "=== save one frame for the picture check ==="
nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 \
	--stream-to=/root/v4l2_perf.yuyv >/dev/null 2>&1
ls -l /root/v4l2_perf.yuyv

echo "=== dmesg: warnings / convert / streaming ==="
dmesg | grep -E 'convert:|v4l2: streaming|convert thread|WARN|BUG' | tail -8

echo "=== load after ==="
uptime
