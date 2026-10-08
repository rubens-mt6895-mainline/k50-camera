#!/bin/sh
# Frame-interval histogram A/B: absolute buckets ("clean <32ms") versus buckets
# relative to the nominal period of the mode in use.
#
# The absolute buckets were chosen for the preview mode, whose VTS we shortened
# to 3300 lines (30.2 ms period).  A 30 fps vendor mode has a 33.33 ms period,
# so every healthy frame of it landed in "late(32-40ms)".  Both legs here select
# 4000x2256 @30 (normal_video, vendor VTS 3658) through S_FMT/S_PARM and stream
# 80 frames, so the two `dist` lines are directly comparable.
#
# Needs two modules on the device:
#   /root/cam_cap_v2.ko    an older build that still has the absolute buckets
#   /root/cam_cap_dist.ko  the current build (buckets relative to nom period)
set -u

load() {	# $1 = module path to become /root/cam_cap.ko
	if grep -q '^cam_cap ' /proc/modules; then rmmod cam_cap || echo "rmmod failed"; fi
	cp -f "$1" /root/cam_cap.ko
	CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh >/dev/null 2>&1
	sh /root/zz_cam_up.sh >/dev/null 2>&1
	[ "$(grep -c '^cam_cap ' /proc/modules)" = 1 ] || { echo "load failed"; exit 1; }
}

leg() {		# $1 = label, $2 = module
	echo "=== $1 ==="
	md5sum "$2"
	load "$2"
	v4l2-ctl -d /dev/video0 --set-fmt-video=width=4000,height=2256,pixelformat=YUYV \
		--set-parm=30 >/dev/null 2>&1
	v4l2-ctl -d /dev/video0 -V 2>&1 | grep -E 'Width/Height' | head -1
	timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=80 --stream-to=/dev/null >/dev/null 2>&1
	grep -E '^(avg|timing|dist)' /proc/camcap_info | cut -c1-150
	echo
}

leg "old build: absolute buckets"   /root/cam_cap_v2.ko
leg "new build: relative buckets"   /root/cam_cap_dist.ko

echo "=== leave the current build on the default preview mode ==="
load /root/cam_cap_dist.ko
v4l2-ctl -d /dev/video0 --set-fmt-video=width=2000,height=1500,pixelformat=YUYV --set-parm=30 >/dev/null 2>&1
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=80 --stream-to=/dev/null >/dev/null 2>&1
grep -E '^(avg|timing|dist|stats)' /proc/camcap_info | cut -c1-150
echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|Unable to handle|Internal error')"
