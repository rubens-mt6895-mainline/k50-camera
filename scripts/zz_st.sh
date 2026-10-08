#!/bin/sh
# Tiny device status: clock, uptime, module, camera info head.
set -u
date
uptime
cat /proc/uptime
echo "--- cam_cap ---"
lsmod | grep cam_cap || echo "(not loaded)"
md5sum /root/cam_cap.ko 2>/dev/null
echo "--- info ---"
grep -E '^(avg|timing|af|ae|stats|source|output)' /proc/camcap_info 2>/dev/null | cut -c1-150
echo "--- video0 ---"
ls -l /dev/video0 2>/dev/null
fuser -v /dev/video0 2>&1 | tail -3
echo "--- load/temp ---"
cat /proc/loadavg
