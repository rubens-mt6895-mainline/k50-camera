#!/bin/sh
# zz_who.sh - who is using the machine / the camera right now (read-only).
echo "=== time / uptime ==="
date; uptime
echo "=== top cpu ==="
ps -eo pid,pcpu,pmem,etime,comm --sort=-pcpu 2>/dev/null | head -12
echo "=== /dev/video0 holders ==="
fuser -v /dev/video0 2>&1
echo "=== cheese ==="
pgrep -a cheese
echo "=== disk ==="
df -h / | tail -2
echo "=== camcap ==="
grep -E "^(avg|stats|ae|awb|source|v4l2)" /proc/camcap_info | head -8
echo "=== other AI traces (recent dmesg from not-cam) ==="
dmesg | grep -c -i "cam_cap"
echo "=== zz_who done ==="
