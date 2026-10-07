#!/bin/sh
# Reproduce + capture the Cheese "cannot connect to camera" failure.
echo "=== who holds /dev/video0 ==="
fuser -v /dev/video0 2>&1
echo "=== arm_count before ==="
grep -E 'arm_count|vf_on' /proc/camcap_info
echo "=== start cheese as k50 (verbose) ==="
pkill -x cheese 2>/dev/null
sleep 1
runuser -u k50 -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  G_MESSAGES_DEBUG=all GST_DEBUG=2 \
  nohup setsid cheese >/tmp/cheese2.log 2>&1 </dev/null &
sleep 12
echo "=== cheese procs ==="
ps -eo pid,pcpu,etime,args | grep -i '[c]heese'
echo "=== arm_count after 12s ==="
grep -E 'arm_count|vf_on|last_result' /proc/camcap_info
echo "=== cheese2.log (first 60) ==="
head -60 /tmp/cheese2.log
echo "=== dmesg cam_cap tail ==="
dmesg | grep -i 'cam_cap\|v4l2\|iommu' | tail -12
echo "=== gst test as k50 ==="
runuser -u k50 -- env XDG_RUNTIME_DIR=/run/user/1000 \
  timeout 20 gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=10 ! fakesink 2>&1 | tail -5
echo "=== done ==="
