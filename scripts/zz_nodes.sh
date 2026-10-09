#!/bin/sh
# Check the multi-node build: load with cam_nodes=4, look at every node an
# application would see (card, formats, frame sizes), stream node 0, then
# reload with the default cam_nodes=1 and confirm the old single-node path is
# unchanged.  Nothing here touches the auxiliary cameras' power: that is
# separate userspace bring-up and is checked by zz_front_cap.sh.
set -u

echo "=== when ==="
date
uptime

echo "=== holders ==="
pkill -x cheese 2>/dev/null && echo "stopped cheese" || echo "cheese not running"
sleep 1

echo "=== module ==="
md5sum /root/cam_cap.ko
if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap && echo "rmmod ok" || echo "rmmod FAILED"
fi
grep -q '^cam_cap ' /proc/modules && { echo "ABORT: cam_cap still loaded"; exit 1; }

echo "=== load with cam_nodes=4 ==="
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh 2>&1 | tail -2
CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh 2>&1 | tail -4

echo "=== load lines ==="
dmesg | grep -E 'cam_cap: (source|mode|output|v4l2: registered)' | tail -10

echo "=== nodes ==="
ls -l /dev/video*
v4l2-ctl --list-devices 2>&1

for i in 0 1 2 3; do
	[ -c "/dev/video$i" ] || continue
	echo "--- /dev/video$i"
	timeout 10 v4l2-ctl -d "/dev/video$i" --info 2>&1 |
		grep -E 'Card type|Driver name|Bus info'
	timeout 10 v4l2-ctl -d "/dev/video$i" --list-formats 2>&1 | grep -E '\[|Pixel'
	timeout 10 v4l2-ctl -d "/dev/video$i" --list-framesizes=YUYV 2>&1 | head -10
	timeout 10 v4l2-ctl -d "/dev/video$i" --get-fmt-video 2>&1 |
		grep -E 'Width/Height|Pixel Format|Field|Bytes per Line|Size Image'
done

echo "=== node 0 streams with cam_nodes=4 ==="
timeout 30 v4l2-ctl -d /dev/video0 --stream-mmap=4 --stream-count=60 \
	--stream-to=/dev/null 2>&1 | tail -2
grep -E '^(avg|timing|dist)' /proc/camcap_info

echo "=== a second node while node 0 is not streaming: s_fmt is allowed, ==="
echo "=== but reqbufs/streamon must still be refused while it is ==="
timeout 20 v4l2-ctl -d /dev/video1 --get-fmt-video 2>&1 |
	sed -n '/Width/p;/Pixel Format/p' | head -4

echo "=== reload with the default (no cam_nodes) ==="
rmmod cam_cap && echo "rmmod ok" || { echo "ABORT: rmmod failed"; exit 1; }
sh /root/zz_cam_up.sh 2>&1 | tail -3
ls -l /dev/video*
timeout 30 v4l2-ctl -d /dev/video0 --stream-mmap=4 --stream-count=60 \
	--stream-to=/dev/null 2>&1 | tail -2
grep -E '^(avg|timing|dist)' /proc/camcap_info

echo "=== arm timeouts (all time) ==="
dmesg | grep -c 'timed out'
echo "=== crashes ==="
dmesg | grep -icE 'Oops|BUG:|panic|segfault|Unable to handle|Internal error|Call trace'
echo "=== stray processes ==="
ps -eo pid,comm,args | grep -E 'v4l2-ctl|cheese' | grep -v grep || echo "(none)"
echo "=== done ==="
