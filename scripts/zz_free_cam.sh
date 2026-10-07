#!/bin/sh
# zz_free_cam.sh - get out of a stuck stream: stop everything that holds the
# camera, unload cam_cap, and bring the default (preview, 2000x1500) stack back
# up exactly the way cam_boot.sh does.
set -u

echo "=== 1. stop everything holding the camera ==="
pgrep -x cheese >/dev/null 2>&1 && { pkill -x cheese; echo "  killed cheese"; }
pkill -x v4l2-ctl 2>/dev/null && echo "  killed v4l2-ctl"
fuser -k /dev/video0 2>/dev/null
sleep 3
echo "  refcnt: $(cat /sys/module/cam_cap/refcnt 2>/dev/null)"
fuser -v /dev/video0 2>&1

echo "=== 2. unload cam_cap ==="
if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap 2>&1
fi
if grep -q '^cam_cap ' /proc/modules; then
	echo "  [!!] cam_cap still in use; open fds:"
	for f in /proc/[0-9]*/fd; do
		ls -l "$f" 2>/dev/null | grep video0 >/dev/null && ls -l "$f" 2>/dev/null | grep video0
	done
	exit 1
fi
echo "  [ok] cam_cap unloaded"

echo "=== 3. bring the default stack back up ==="
MODE_W=4000 MODE_H=3000 MODE_STRIDE=6000 MODE_FRAME=18874368 \
	sh /root/zz_v80.sh 2>&1 | tail -8
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 exp_max=3172 conv_threads=4 v4l2_bin=2 pipeline=1" \
	sh /root/zz_cam_up.sh 2>&1 | tail -12

echo "=== 4. liveness check ==="
nice -n 10 v4l2-ctl --stream-mmap --stream-count=30 --stream-to=/dev/null 2>&1 \
	| grep -oE '[0-9]+\.[0-9]+ fps' | tail -1
grep -E '^(stats|ae|avg|dist)' /proc/camcap_info 2>/dev/null
echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
dmesg | tail -4
echo "### zz_free_cam done"
