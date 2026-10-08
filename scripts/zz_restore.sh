#!/bin/sh
# Put the device back on the default preview stack with the fixed module
# (/root/cam_cap.ko, pushed by the caller) and verify it captures.
set -u

echo "=== modules before ==="
lsmod | grep -c cam_cap
md5sum /root/cam_cap.ko /root/cam_cap_new.ko /root/cam_cap_v2.ko 2>/dev/null

echo "=== unload if loaded ==="
if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap && echo "rmmod ok" || echo "rmmod FAILED"
fi

echo "=== bring up rails then camera (same order as cam_boot.sh) ==="
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh 2>&1 | tail -4
sh /root/zz_cam_up.sh 2>&1 | tail -6

echo "=== verify ==="
ls -l /dev/video0
grep -E '^(avg|stats|af|ae|timing)' /proc/camcap_info 2>/dev/null | head -8

echo "=== live check: 20 frames ==="
timeout 12 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=20 --stream-to=/dev/null 2>&1 | tail -3
grep -E '^(avg|timing)' /proc/camcap_info 2>/dev/null

echo "=== crashes ==="
dmesg | grep -icE 'Oops|BUG:|panic|segfault|Unable to handle|Internal error'
