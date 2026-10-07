#!/bin/sh
# zz_accept.sh - acceptance run for the converter optimisation.
#
# Loads the module with nothing but the defaults (conv_threads=8, pipe_slots=3,
# v4l2_bin=2), then walks the modes a user can reach through VIDIOC_S_FMT /
# VIDIOC_S_PARM and reports what each one actually delivers.
set -u
P=/sys/module/cam_cap/parameters
I=/proc/camcap_info

show() {
	grep -E '^(avg|timing|dist|stats)' $I | sed 's/^/  /'
}

stream() {
	timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count="$1" 2>&1 | tail -1
}

echo "=== free the camera ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap 2>&1 || { echo "ABORT: cam_cap in use"; exit 1; }
fi
dmesg -c >/dev/null

echo "=== load with defaults only ==="
insmod /root/cam_cap.ko v4l2_enable=1 || { echo "ABORT: insmod failed"; exit 1; }
dmesg | grep -E 'source:|mode:|output:|pipeline: frame buffer|register|convert:' | sed 's/^/  /'
for p in conv_threads pipe_slots v4l2_bin out_width out_height; do
	printf '  %s = %s\n' "$p" "$(cat $P/$p)"
done

echo 0 > $P/af_enable

echo
echo "=== enum ==="
timeout 20 v4l2-ctl -d /dev/video0 --list-formats-ext 2>&1 | head -30

echo
echo "=== preview binned 2000x1500 (sensor ceiling ~33) ==="
stream 60
show

echo
echo "=== custom2 native 1920x1080 @120 ==="
timeout 25 v4l2-ctl -d /dev/video0 -v width=1920,height=1080 >/dev/null 2>&1
timeout 25 v4l2-ctl -d /dev/video0 --set-parm=120 >/dev/null 2>&1
stream 120
show

echo
echo "=== custom3 half size 2000x1128 @60 ==="
timeout 25 v4l2-ctl -d /dev/video0 -v width=2000,height=1128 >/dev/null 2>&1
timeout 25 v4l2-ctl -d /dev/video0 --set-parm=60 >/dev/null 2>&1
stream 120
show

echo
echo "=== custom3 native 4000x2256 @60 ==="
timeout 25 v4l2-ctl -d /dev/video0 -v width=4000,height=2256 >/dev/null 2>&1
timeout 25 v4l2-ctl -d /dev/video0 --set-parm=60 >/dev/null 2>&1
stream 120
show

echo
echo "=== normal_video native 4000x2256 @30 ==="
timeout 25 v4l2-ctl -d /dev/video0 -v width=4000,height=2256 >/dev/null 2>&1
timeout 25 v4l2-ctl -d /dev/video0 --set-parm=30 >/dev/null 2>&1
stream 60
show

echo
echo "=== restore the boot configuration (preview, binned) ==="
echo "mode preview 2" > /proc/camcap
stream 60
show

echo
echo "=== health ==="
dmesg | grep -ciE 'oops|BUG|panic|watchdog' || true
cat /proc/loadavg
uptime
