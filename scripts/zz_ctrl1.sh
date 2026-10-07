#!/bin/sh
# zz_ctrl1.sh - load the new cam_cap.ko with the AE/AWB code and show the controls.
# Device side.  One device task at a time: this script starts no background work.
set -u

echo "=== uptime / load ==="
uptime 2>/dev/null
echo

echo "=== v4l2 base modules ==="
grep -E '^(mc|videodev|videobuf2_[a-z]+) ' /proc/modules | awk '{print $1, $3}'
echo

echo "=== stop anything using the camera ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
echo "cheese left: $(pgrep -c -x cheese 2>/dev/null || echo 0)"
echo

echo "=== reload cam_cap with v4l2_enable=1 ==="
rmmod cam_cap 2>&1
sleep 1
insmod /root/cam_cap.ko v4l2_enable=1 2>&1
echo "insmod rc=$?"
sleep 2

echo "=== device node ==="
ls -l /dev/video0 2>&1
echo

echo "=== module parameters that matter ==="
for p in v4l2_enable pak_mode pak_dbl dbl_data_bus route_pix_mode single_mode \
	 frame_bytes sensor_ctl i2c_bus i2c_addr ae_enable awb_enable ae_target \
	 exp_max again_max dgain_max; do
	printf '%-16s %s\n' "$p" "$(cat /sys/module/cam_cap/parameters/$p 2>/dev/null)"
done
echo

echo "=== dmesg (cam_cap / v4l2 / i2c) ==="
dmesg | grep -Ei 'cam_cap|v4l2|i2c' | tail -25
echo

echo "=== /proc/camcap_info ==="
cat /proc/camcap_info 2>&1
echo

echo "=== handler / controls ==="
v4l2-ctl -d /dev/video0 --list-ctrls 2>&1
