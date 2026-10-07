#!/bin/sh
# zz_b60.sh [pipe_slots] [frames] - where does 60/120 fps actually land?
#
# Reloads the module with the requested pipeline depth and measures, with 8 mmap
# buffers (v4l2-ctl's default 4 starve the pipeline a little), the native and the
# half-size (bin=2) output of the two high-rate sensor modes, plus a baseline.
#
#   custom3 4000x2256@60 native bin=1     custom3 2000x1128@60 bin=2
#   custom2 1920x1080@120 native bin=1    custom2  960x540@120 bin=2
#   hs_video 1920x1080@240 native bin=1   (240 is out of scope, reported anyway)
set -u
SL=${1:-3}
NF=${2:-120}
P=/sys/module/cam_cap/parameters
I=/proc/camcap_info

show() {
	echo "--- $1"
	grep -E '^(avg|timing|dist|stats)' $I | sed 's/^/  /'
}

echo "=== free the camera ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap 2>&1 || { echo "ABORT: cam_cap still in use"; exit 1; }
fi
dmesg -c >/dev/null

echo "=== reload: conv_threads=8 pipe_slots=$SL ==="
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=8 pipe_slots=$SL pipeline=1 || {
	echo "ABORT: insmod failed"; exit 1; }
echo "conv_threads=$(cat $P/conv_threads) pipe_slots=$(cat $P/pipe_slots)"
echo "v4l2_bin=$(cat $P/v4l2_bin) out=$(cat $P/out_width)x$(cat $P/out_height)"
dmesg | grep -E 'pipeline: frame buffer|registered /dev/video0'
echo 0 > $P/af_enable

echo
echo "=== baseline: mode preview 2 (2000x1500) ==="
echo "mode preview 2" > /proc/camcap
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=60 >/dev/null 2>&1
show baseline

echo
echo "=== custom3 native 4000x2256 @60 (bin 1) ==="
timeout 20 v4l2-ctl -d /dev/video0 -v width=4000,height=2256 >/dev/null 2>&1
timeout 20 v4l2-ctl -d /dev/video0 --set-parm=60 >/dev/null 2>&1
dmesg | tail -2
timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$NF 2>&1 | tail -1
show custom3-bin1

echo
echo "=== custom3 half size 2000x1128 @60 (bin 2) ==="
timeout 20 v4l2-ctl -d /dev/video0 -v width=2000,height=1128 >/dev/null 2>&1
timeout 20 v4l2-ctl -d /dev/video0 --set-parm=60 >/dev/null 2>&1
dmesg | tail -2
timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$NF 2>&1 | tail -1
show custom3-bin2

echo
echo "=== custom2 native 1920x1080 @120 (bin 1) ==="
timeout 20 v4l2-ctl -d /dev/video0 -v width=1920,height=1080 >/dev/null 2>&1
timeout 20 v4l2-ctl -d /dev/video0 --set-parm=120 >/dev/null 2>&1
dmesg | tail -2
timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$NF 2>&1 | tail -1
show custom2-bin1

echo
echo "=== custom2 half size 960x540 @120 (bin 2) ==="
timeout 20 v4l2-ctl -d /dev/video0 -v width=960,height=540 >/dev/null 2>&1
timeout 20 v4l2-ctl -d /dev/video0 --set-parm=120 >/dev/null 2>&1
dmesg | tail -2
timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$NF 2>&1 | tail -1
show custom2-bin2

echo
echo "=== restore: mode preview 2 ==="
echo "mode preview 2" > /proc/camcap
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=60 >/dev/null 2>&1
show restored

echo
echo "=== health ==="
dmesg | grep -ciE 'oops|BUG|panic|watchdog' || true
cat /proc/loadavg
free -m | head -2
