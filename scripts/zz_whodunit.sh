#!/bin/sh
# zz_whodunit.sh - after the unexplained reboot: how did it come back, and why?
set -u

echo "=== uptime / now ==="
uptime
date

echo "=== boot history ==="
last -x reboot shutdown 2>/dev/null | head -12

echo "=== previous boot tail (journal, if persistent) ==="
journalctl --list-boots 2>/dev/null | tail -5
echo "--- last 40 lines of the previous boot ---"
journalctl -b -1 -n 40 --no-pager 2>/dev/null | tail -40

echo "=== current boot dmesg head ==="
dmesg | head -5

echo "=== current boot dmesg: anything ugly ==="
dmesg | grep -iE 'panic|oops|BUG:|watchdog|thermal|shutdown|reboot|out of memory|oom' | tail -15

echo "=== cam_cap / video nodes ==="
grep -E '^cam_cap|^videodev|^mc ' /proc/modules
ls -l /dev/video* 2>/dev/null

echo "=== camera users right now ==="
echo "v4l2-ctl: $(pgrep -c -x v4l2-ctl 2>/dev/null || echo 0)"
echo "cheese  : $(pgrep -c -x cheese 2>/dev/null || echo 0)"
echo "gst     : $(pgrep -c -f gst-launch 2>/dev/null || echo 0)"
fuser -v /dev/video0 2>&1 | head -5

echo "=== load ==="
cat /proc/loadavg
