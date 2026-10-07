#!/bin/sh
# zz_sfmt_perf.sh [conv_threads] [pipe_slots] [frames]
#
# Reload cam_cap with a given conversion-pool size and pipeline depth, then
# stream every full-size mode once and report where the time goes.  The sensor
# is put back on the preview table through the driver's own replay, so the run
# is self-contained after an rmmod.
set -u
TH=${1:-8}
SL=${2:-3}
NF=${3:-60}
P=/sys/module/cam_cap/parameters

echo "=== free the camera ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

echo "=== reload cam_cap: conv_threads=$TH pipe_slots=$SL ==="
rmmod cam_cap 2>/dev/null || { echo "ABORT: cam_cap is still in use"; exit 1; }
dmesg -c >/dev/null
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=$TH pipe_slots=$SL pipeline=1 \
	|| { echo "ABORT: insmod failed"; exit 1; }
sleep 1
dmesg | grep -E 'cam_cap: (pipeline|convert|source|v4l2)' | head -14

echo 0 > /sys/module/cam_cap/parameters/af_enable 2>/dev/null
echo "conv_threads=$(cat $P/conv_threads) pipe_slots=$(cat $P/pipe_slots) pipeline=$(cat $P/pipeline)"

echo ""
echo "=== sensor back to preview (driver replay) ==="
echo "mode preview 2" > /proc/camcap || echo "  mode command failed"
sleep 0.5
grep -E '^output' /proc/camcap_info

measure() { # label
	echo ""
	echo "=== $1 ==="
	timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$NF \
		--stream-to=/dev/null >/dev/null 2>&1
	echo "  stream rc=$?"
	dmesg | grep -E 'cam_cap: (mode:|rx:|v4l2: s_)' | tail -3
	grep -E '^(avg|timing|dist|stats)' /proc/camcap_info
}

# 1920x1080, custom2 (1370 Mbps, 120 fps ceiling)
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=YUYV >/dev/null 2>&1
v4l2-ctl -d /dev/video0 --set-parm=120 >/dev/null 2>&1
measure "custom2 1920x1080 (120 fps ceiling)"

# 1920x1080, hs_video (1964 Mbps, 240 fps ceiling): conversion ceiling only
v4l2-ctl -d /dev/video0 --set-parm=240 >/dev/null 2>&1
measure "hs_video 1920x1080 (240 fps ceiling)"

# 4000x2256, custom3 (1964 Mbps, 60 fps ceiling)
v4l2-ctl -d /dev/video0 --set-fmt-video=width=4000,height=2256,pixelformat=YUYV >/dev/null 2>&1
v4l2-ctl -d /dev/video0 --set-parm=60 >/dev/null 2>&1
measure "custom3 4000x2256 (60 fps ceiling)"

# 4000x2256, normal_video (1370 Mbps, 30 fps ceiling)
v4l2-ctl -d /dev/video0 --set-fmt-video=width=4000,height=2256,pixelformat=YUYV >/dev/null 2>&1
v4l2-ctl -d /dev/video0 --set-parm=30 >/dev/null 2>&1
measure "normal_video 4000x2256 (30 fps ceiling)"

# back to the default geometry
v4l2-ctl -d /dev/video0 --set-fmt-video=width=2000,height=1500,pixelformat=YUYV >/dev/null 2>&1
measure "preview binned 2000x1500 (33 fps ceiling)"

echo ""
echo "=== health ==="
cat /proc/loadavg
dmesg | grep -ciE 'oops|BUG:|panic|watchdog'
echo done
