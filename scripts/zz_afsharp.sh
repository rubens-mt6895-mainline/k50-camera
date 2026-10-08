#!/bin/sh
# zz_afsharp.sh - capture a frame at a few lens positions and print the driver's
# own metric there, so the sharpness can be compared off-device.  Answers two
# questions at once:
#   * does writing a DAC position actually move the lens? (compare the frames)
#   * does the driver's focus metric track that change? (compare "metric=")
set -u

NF=${1:-3}

echo "=== full cam_af history ==="
dmesg | grep -E "cam_af" | tail -40
echo "=== af line before ==="
grep -E "^af" /proc/camcap_info

for p in 0 256 512 768 1023; do
	echo "af pos $p" > /proc/camcap
	sleep 2
	echo "--- pos $p ---"
	timeout 25 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$NF \
		--stream-to=/root/sharp_$p.yuyv >/dev/null 2>&1
	grep -E "^af" /proc/camcap_info
done

echo "=== restore 512 (manual) ==="
echo "af pos 512" > /proc/camcap
sleep 2
grep -E "^af" /proc/camcap_info
ls -l /root/sharp_*.yuyv
dmesg | grep -E "oops|BUG|panic|Call trace" | tail -3
uptime
