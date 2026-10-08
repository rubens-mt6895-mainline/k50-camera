#!/bin/sh
# zz_bootpath.sh - prove the boot path registers cam_cap exactly once now
# (CAM_V80_NO_INSMOD=1 in cam_boot.sh, so only zz_cam_up.sh loads the module).
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "=== 1. boot scripts on the device ==="
grep -n 'CAM_V80_NO_INSMOD' /root/cam_boot.sh /root/zz_v80.sh /root/zz_cam_up.sh 2>&1
echo "--- cam_boot.sh calls ---"
grep -n 'zz_v80.sh\|zz_cam_up.sh' /root/cam_boot.sh 2>&1

echo
echo "=== 2. free the device and clear dmesg ==="
pkill -x cheese 2>/dev/null
pkill -x guvcview 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 2
rmmod cam_cap 2>&1
dmesg -c >/dev/null
echo "module loaded? $(lsmod | grep -c '^cam_cap ')"

echo
echo "=== 3. run the real boot path ==="
timeout 200 sh /root/cam_boot.sh 2>&1 | grep -nE 'insmod|rmmod|removed|leaving cam_cap|cam_cap|registered|\[ok\]|\[!!\]|rc=' | tail -30
echo "boot path rc=$?"

echo
echo "=== 4. what dmesg recorded ==="
echo "--- cam_cap registration lines ---"
dmesg | grep -nE 'cam_cap: (v4l2: registered|source:|output:|loaded:)' 2>&1
echo "--- counts ---"
echo "registered: $(dmesg | grep -c 'v4l2: registered')"
echo "loaded:     $(dmesg | grep -c 'loaded: CAMSV')"
echo "rmmod/removing: $(dmesg | grep -ciE 'removing|unloaded')"

echo
echo "=== 5. state ==="
ls -l /dev/video0 2>&1
echo "sysfs: $(ls /sys/class/video4linux/ 2>/dev/null | tr '\n' ' ')"
lsmod | grep '^cam_cap ' 2>&1
grep -E '^(vf_on|arm_count|frame_ready|last_result)' /proc/camcap_info 2>/dev/null | head -4
echo "crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog')"
uptime
echo "=== zz_bootpath done ==="
