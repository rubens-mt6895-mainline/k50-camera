#!/bin/sh
# zz_boot_check.sh - strict acceptance for the single-registration boot path
# (cam_boot.sh sets CAM_V80_NO_INSMOD=1, so only zz_cam_up.sh loads cam_cap).
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "=== zz_boot_check ==="
date
uptime
echo "boot_id: $(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
echo "cmdline: $(tr ' ' '\n' </proc/cmdline | grep -iE 'root|androidboot' | head -4 | tr '\n' ' ')"

echo "--- 1. cam-camera.service"
echo "enabled: $(systemctl is-enabled cam-camera.service 2>&1)"
echo "active : $(systemctl is-active cam-camera.service 2>&1)"
systemctl --no-pager -l status cam-camera.service 2>&1 | head -14
echo "--- /var/log/cam_boot.log (tail)"
tail -14 /var/log/cam_boot.log 2>/dev/null

echo "--- 2. registration accounting over the whole boot"
echo "registered : $(dmesg | grep -c 'v4l2: registered')   (want 1)"
echo "loaded     : $(dmesg | grep -c 'loaded: CAMSV')     (want 1)"
echo "removal    : $(dmesg | grep -ciE 'unloaded|removed') (want 0)"
dmesg | grep -E 'cam_cap: (v4l2: registered|loaded:|source:|output:|route)' | head -12
echo "  removal lines:"
dmesg | grep -iE 'cam_cap.*(removed|unloaded)' | head -6
echo "  insmod retries (first attempt may fail before v4l2 base is up):"
dmesg | grep -c 'Unknown symbol'

echo "--- 3. v4l2 nodes"
ls -l /dev/video0 2>&1
echo "sysfs: $(ls /sys/class/video4linux/ 2>/dev/null | tr '\n' ' ')"
echo "--- gstreamer device count"
if [ -e /root/gst_enum.py ]; then
	python3 /root/gst_enum.py 2>/dev/null | grep -E 'count|display|path|driver' | head -8
elif [ -e /tmp/gst_enum.py ]; then
	python3 /tmp/gst_enum.py 2>/dev/null | grep -E 'count|display|path|driver' | head -8
else
	echo "  (no gst_enum.py on the device)"
fi

echo "--- 4. live capture"
timeout 25 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=20 --stream-to=/dev/null 2>&1 | tail -3
grep -E '^(source|mode |output|vf_on|arm_count|frame_ready|last_result|avg|timing|stats|af)' \
	/proc/camcap_info 2>/dev/null | head -10

echo "--- 5. health"
echo "crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog|Unable to handle')"
free | head -2
uptime
echo "=== zz_boot_check done ==="
