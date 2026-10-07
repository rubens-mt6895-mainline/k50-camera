#!/bin/sh
# zz_final_state.sh - leave-behind state check.
echo "=== uptime / load ==="
uptime
echo
echo "=== service ==="
systemctl is-enabled cam-camera.service 2>&1
systemctl is-active cam-camera.service 2>&1
echo
echo "=== camera devices ==="
ls -l /dev/video0 2>/dev/null || echo "  /dev/video0 missing"
echo "  name: $(cat /sys/class/video4linux/video0/name 2>/dev/null)"
echo "  holders: [$(fuser /dev/video0 2>&1)]"
echo
echo "=== cheese ==="
pgrep -a cheese 2>/dev/null || echo "  not running"
echo
echo "=== driver params ==="
for p in v4l2_enable conv_threads v4l2_gain_q8 v4l2_black ae_target again_max exp_max frame_bytes route_once; do
	echo "  $p = $(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)"
done
echo
echo "=== camcap_info ==="
grep -E 'frame_ready|arm_count|last_result|convert :|avg|stats' /proc/camcap_info 2>/dev/null
echo
echo "=== crash scan ==="
echo "  Oops/paging in dmesg: $(dmesg | grep -ciE 'Oops|paging request')"
echo "  last 3 dmesg:"
dmesg | tail -3 | sed 's/^/    /'
echo
echo "=== /root assets installed ==="
ls -l /root/cam_boot.sh /root/cam_reset.sh /etc/systemd/system/cam-camera.service 2>/dev/null
echo
echo "=== cam_boot.log last line ==="
tail -1 /var/log/cam_boot.log 2>/dev/null
