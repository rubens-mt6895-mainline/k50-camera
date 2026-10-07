#!/bin/sh
# zz_pre.sh - read-only pre-flight for the mode drill: time left, CMA, module state.
echo "=== time / load ==="
date; uptime
echo "=== CMA / memory ==="
grep -i cma /proc/meminfo
grep -E 'MemTotal|MemAvailable' /proc/meminfo
echo "=== modules ==="
grep -E '^cam_|^video|^vb2|^mc ' /proc/modules | awk '{print "  "$1" "$2" refs="$3" "$5}'
echo "=== processes ==="
pgrep -a -x cheese; pgrep -a v4l2-ctl; pgrep -a cam_cap
echo "=== /dev/video0 ==="
ls -l /dev/video0 2>&1
echo "=== /root files ==="
ls -l /root/cam_cap.ko 2>&1
ls -l /root/mode_*.txt 2>&1
ls -l /root/zz_v80.sh /root/zz_cam_up.sh /root/imx582_bring.py 2>&1
echo "=== live params ==="
for p in exp_hsize exp_vsize v4l2_src_stride exp_max conv_threads pipeline rb_swap frame_bytes out_width out_height; do
	v=$(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)
	echo "  $p = $v"
done
echo "=== info head ==="
grep -E '^(source|buffer|v4l2|avg|stats|ae|awb|dist)' /proc/camcap_info 2>/dev/null | head -12
echo "=== dmesg tail ==="
dmesg | tail -4
echo "=== zz_pre done ==="
