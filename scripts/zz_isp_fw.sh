#!/bin/sh
# zz_isp_fw.sh - is any ISP-related firmware / remoteproc present on this device?
# Run on the K50 through zz_app_run.sh. Read-only, low load.
echo "=== uptime / load ==="
uptime
echo
echo "=== /lib/firmware ==="
ls /lib/firmware 2>/dev/null | head -20
echo "count: $(ls /lib/firmware 2>/dev/null | wc -l)"
echo
echo "=== mediatek firmware subdir ==="
ls /lib/firmware/mediatek 2>/dev/null | head -20
ls /lib/firmware/vpu 2>/dev/null | head -10
echo
echo "=== anything named ccu/isp/imgsys in firmware dirs ==="
for d in /lib/firmware /lib/firmware/mediatek /vendor/firmware /odm/firmware /system/etc/firmware; do
  [ -d "$d" ] || continue
  ls "$d" 2>/dev/null | grep -iE 'ccu|isp|imgsys|imgsensor' | head -10
done
echo
echo "=== android partitions present? ==="
ls -d /vendor /odm /system /system_ext 2>/dev/null
echo "--- mounts ---"
grep -E ' /(vendor|system|odm)[ _/]' /proc/mounts 2>/dev/null | head -5
echo
echo "=== remoteproc / rpmsg ==="
ls /sys/class/remoteproc 2>/dev/null
ls /sys/bus/rpmsg/devices 2>/dev/null | head -5
echo
echo "=== device tree: ccu / camisp / imgsys nodes ==="
ls /sys/firmware/devicetree/base 2>/dev/null | grep -iE 'ccu|camisp|imgsys|camsys' | head -10
echo
echo "=== current cheese / cam_cap state ==="
pgrep -a cheese 2>/dev/null | head -3
echo "cheese_pids=$(pgrep -c cheese 2>/dev/null)"
cat /sys/module/cam_cap/parameters/v4l2_enable 2>/dev/null
grep -E 'frame_ready|arm_count|last_seq' /proc/camcap_info 2>/dev/null
echo "--- load ---"
uptime
