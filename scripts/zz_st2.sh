#!/bin/sh
# zz_st2.sh - quick device status: is cheese alive, is the camera streaming,
# and how loaded is the box?
echo "=== uptime ==="
cat /proc/uptime
uptime
echo "=== cheese ==="
pgrep -a cheese 2>&1
echo "=== cheese log ==="
tail -6 /tmp/cheese.log 2>&1
echo "=== camcap ==="
grep -E 'frame_ready|arm_count|last_seq|vf_on' /proc/camcap_info 2>&1
echo "=== top 8 by cpu ==="
ps -eo pid,pcpu,comm --sort=-pcpu 2>/dev/null | head -9
echo "=== cheese media ==="
ls -l /home/k50/.gnome2/cheese/media/ 2>&1 | tail -4
echo "=== disk ==="
df -h /home 2>&1 | tail -1
echo "=== done ==="
