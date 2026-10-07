#!/bin/sh
# Device-side: what is the current camera stack state?
echo "=== uptime / load ==="
uptime
echo "=== modules ==="
grep -E '^(cam_cap|mc|videodev|videobuf2)' /proc/modules | awk '{print $1, $3, $5}'
echo "=== /dev/video* ==="
ls -l /dev/video* 2>&1
echo "=== /proc/devices video ==="
grep -i video /proc/devices
echo "=== /root/v4l2 ==="
ls -l /root/v4l2/ 2>&1 | head -20
echo "=== cam_cap params (key) ==="
for p in v4l2_enable ae_enable ae_target ae_band ae_clip_pct awb_enable exp_max again_max dgain_max single_mode frame_bytes; do
  printf '%-14s %s\n' "$p" "$(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)"
done
echo "=== camcap_info ==="
cat /proc/camcap_info 2>&1 | tail -12
echo "=== cheese procs ==="
ps -eo pid,pcpu,etime,args 2>/dev/null | grep -i cheese | grep -v grep
echo "=== cheese log tail ==="
tail -25 /tmp/cheese.log 2>&1
echo "=== dmesg tail ==="
dmesg | tail -20
echo "=== done ==="
