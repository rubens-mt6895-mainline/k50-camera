#!/bin/sh
# zz_recover_dev.sh - device side, post-reboot: sensor bring-up + V4L2 stack.
# Refuses to start if somebody else is already using the camera.
set -u

echo "=== guard: is anyone else on the camera? ==="
for p in v4l2-ctl cheese gst-launch-1.0 ffmpeg; do
	n=$(pgrep -c -x "$p" 2>/dev/null)
	[ -z "$n" ] && n=0
	echo "  $p: $n"
	if [ "$n" -gt 0 ]; then
		echo "  ABORT: $p is running - not touching the camera"
		exit 1
	fi
done

for f in /root/zz_v80.sh /root/zz_cam_up.sh; do
	[ -f "$f" ] || { echo "ABORT: missing $f"; exit 1; }
done

echo
echo "=== 1. sensor bring-up (zz_v80.sh, steps 1-11) ==="
sh /root/zz_v80.sh 2>&1 | tail -32

echo
echo "=== 2. V4L2 stack (zz_cam_up.sh) ==="
sh /root/zz_cam_up.sh 2>&1 | tail -28

echo
echo "=== 3. final state ==="
grep -E 'convert|timing' /proc/camcap_info 2>/dev/null
grep -E '^cam_cap ' /proc/modules
cat /proc/loadavg
