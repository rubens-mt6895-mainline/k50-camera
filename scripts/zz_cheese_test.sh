#!/bin/sh
# zz_cheese_test.sh - reproduce the two Cheese symptoms with the field fix
# loaded: (a) a duplicated caps entry / device, (b) a stall when the format
# changes or a second pipeline opens the device.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
GST="timeout 30 gst-launch-1.0 -e"

echo "=== 0 free the camera ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
fuser -v /dev/video0 2>&1 | head -3

echo "=== 1 reload cam_cap with the new build ==="
rmmod cam_cap 2>&1 || echo "rmmod failed"
dmesg -c >/dev/null
sh /root/zz_v80.sh >/tmp/v80.log 2>&1
echo "v80 rc=$?"
sh /root/zz_cam_up.sh >/tmp/up.log 2>&1
echo "up rc=$?"
sleep 1
dmesg | grep -E 'cam_cap: (source|output|v4l2: registered|mode)' | tail -6

echo "=== 2 field probe (alternate must now fail) ==="
v4l2-ctl -d /dev/video0 --try-fmt-video=width=960,height=540,pixelformat=YUYV,field=alternate >/dev/null 2>&1
echo "alternate rc=$?"
v4l2-ctl -d /dev/video0 --try-fmt-video=width=960,height=540,pixelformat=YUYV,field=none >/dev/null 2>&1
echo "none rc=$?"

echo "=== 3 GstDeviceMonitor enumeration ==="
timeout 90 python3 /tmp/gst_enum.py 2>&1 | head -30

echo "=== 4 single pipeline 2000x1500 ==="
( $GST v4l2src device=/dev/video0 ! video/x-raw,format=YUY2,width=2000,height=1500 ! fakesink num-buffers=60 ) >/tmp/g1.log 2>&1
echo "g1 rc=$?"
tail -2 /tmp/g1.log

echo "=== 5 single pipeline 1920x1080 ==="
( $GST v4l2src device=/dev/video0 ! video/x-raw,format=YUY2,width=1920,height=1080 ! fakesink num-buffers=60 ) >/tmp/g2.log 2>&1
echo "g2 rc=$?"
tail -2 /tmp/g2.log

echo "=== 6 two concurrent pipelines ==="
( $GST v4l2src device=/dev/video0 ! video/x-raw,format=YUY2,width=2000,height=1500 ! fakesink num-buffers=90 ) >/tmp/g3a.log 2>&1 &
A=$!
sleep 3
( $GST v4l2src device=/dev/video0 ! video/x-raw,format=YUY2,width=1920,height=1080 ! fakesink num-buffers=30 ) >/tmp/g3b.log 2>&1 &
B=$!
wait $A
echo "g3a rc=$?"
tail -2 /tmp/g3a.log
wait $B
echo "g3b rc=$?"
tail -2 /tmp/g3b.log

echo "=== 7 dmesg (cam_cap) ==="
dmesg | grep -E 'cam_cap: (v4l2|mode|arm)' | tail -20

echo "=== 9 fresh Cheese as k50, capture what it sees ==="
rm -f /tmp/cheese_dbg.log
chmod 666 /tmp/cheese_dbg.log 2>/dev/null
su k50 -s /bin/sh -c 'export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DISPLAY=:0; GST_DEBUG=GstDeviceMonitor:6 G_MESSAGES_DEBUG=all timeout 25 cheese > /tmp/cheese_dbg.log 2>&1'
echo "cheese rc=$?"
echo "--- device lines in Cheese's own log ---"
grep -nE 'MT6895|v4l2device|video[0-9]|device added|device removed' /tmp/cheese_dbg.log | head -25
echo "--- log size: $(wc -l < /tmp/cheese_dbg.log 2>/dev/null) lines ---"
pkill -x cheese 2>/dev/null
sleep 1

echo "=== 8 health ==="
lsmod | grep -E '^cam_cap' | head -2
grep -E '^(vf_on|frames|arm_count|last_result|int_status)' /proc/camcap_info 2>/dev/null | head -6
free -m | head -2
uptime
echo "crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog')"
echo "=== zz_cheese_test done ==="
