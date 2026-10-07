#!/bin/sh
# zz_alive.sh - is the device up and what was it doing when ssh timed out?
set -u

echo "=== uptime / load ==="
uptime 2>/dev/null
cat /proc/loadavg

echo "=== top cpu consumers ==="
top -b -n 1 2>/dev/null | head -14

echo "=== camera users ==="
echo "v4l2-ctl: $(pgrep -c -x v4l2-ctl 2>/dev/null || echo 0)"
echo "cheese  : $(pgrep -c -x cheese 2>/dev/null || echo 0)"
echo "gst     : $(pgrep -c -f gst-launch 2>/dev/null || echo 0)"
fuser -v /dev/video0 2>&1 | head -5

echo "=== cam_cap ==="
grep -E '^cam_cap ' /proc/modules
ls -l /dev/video0

echo "=== camcap_info (key lines) ==="
grep -E 'convert|timing|stats|ae |awb |arm_count' /proc/camcap_info

echo "=== dmesg tail ==="
dmesg | tail -12
