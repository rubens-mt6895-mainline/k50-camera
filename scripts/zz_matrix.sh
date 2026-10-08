#!/bin/sh
# Per-mode frame-interval matrix with the *new* (relative) buckets.
# Everything is done through S_FMT / S_PARM on the already loaded stack, so no
# module reload and no rail re-power is needed.
#
# Note: the sizes here are *output* sizes.  1920x1080 selects custom2 at 120 fps
# with S_PARM=120 and hs_video at 240 fps with S_PARM=240; 4000x2256 selects
# vendor-VTS 30 fps (normal_video) or 60 fps (custom3).
set -u
D=/dev/video0

run() {		# $1=W $2=H $3=fps $4=frames $5=label
	echo "=== $5 : ${1}x${2} @${3} , ${4} frames ==="
	v4l2-ctl -d $D --set-fmt-video=width=$1,height=$2,pixelformat=YUYV --set-parm=$3 >/dev/null 2>&1
	v4l2-ctl -d $D -V 2>&1 | grep -E 'Width/Height' | head -1
	timeout 120 v4l2-ctl -d $D --stream-mmap --stream-count=$4 --stream-to=/dev/null >/dev/null 2>&1
	grep -E '^(timing|avg|dist|stats)' /proc/camcap_info | cut -c1-155
	echo
}

echo "clock: $(date '+%F %T %Z')  uptime:$(cut -d' ' -f1 /proc/uptime)s  load:$(cut -d' ' -f1-3 /proc/loadavg)"
echo "ko: $(md5sum /root/cam_cap.ko | cut -d' ' -f1)  params: bin=$(cat /sys/module/cam_cap/parameters/v4l2_bin) nt=$(cat /sys/module/cam_cap/parameters/conv_threads) pipe=$(cat /sys/module/cam_cap/parameters/pipeline) slots=$(cat /sys/module/cam_cap/parameters/pipe_slots)"
echo

run 2000 1500 30  100 "preview binned (sensor ceiling 33.3)"
run 4000 2256 30  100 "normal_video full size"
run 4000 2256 60  150 "custom3 60 fps"
run 1920 1080 120 300 "custom2 120 fps"
run 1920 1080 240 300 "hs_video 240 fps"
run 4000 3000 30   60 "preview full size (bin1)"

echo "=== back to the default preview mode ==="
v4l2-ctl -d $D --set-fmt-video=width=2000,height=1500,pixelformat=YUYV --set-parm=30 >/dev/null 2>&1
v4l2-ctl -d $D -V 2>&1 | grep -E 'Width/Height' | head -1
timeout 40 v4l2-ctl -d $D --stream-mmap --stream-count=80 --stream-to=/dev/null >/dev/null 2>&1
grep -E '^(timing|avg|dist|stats)' /proc/camcap_info | cut -c1-155
echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|Unable to handle|Internal error')"
echo "load: $(cut -d' ' -f1-3 /proc/loadavg)"
