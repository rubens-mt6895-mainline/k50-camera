#!/bin/sh
# zz_coldstart.sh - the boot path without a reboot: drop cam_cap, re-run the
# sensor bring-up (which now programs VTS 3500) and bring the V4L2 stack back
# up, then measure.  This is what proves the frame rate fix survives a cold
# start instead of only the running module.
set -u

echo "=== 0. clear the camera ==="
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap || { echo "ABORT: rmmod cam_cap failed"; exit 1; }
	echo "cam_cap removed"
fi

echo
echo "=== 1. sensor bring-up (zz_v80.sh, VTS 3500) ==="
sh /root/zz_v80.sh 2>&1 | tail -34

echo
echo "=== 2. sensor registers after bring-up ==="
rd2() { i2ctransfer -y -f 10 w2@0x10 "$1" "$2" r2@0x10 2>&1; }
echo "  VTS   (0x0340) = $(rd2 0x03 0x40)"
echo "  HTS   (0x0342) = $(rd2 0x03 0x42)"
echo "  EXP   (0x0202) = $(rd2 0x02 0x02)"
echo "  AGAIN (0x0204) = $(rd2 0x02 0x04)"
echo "  DGAIN (0x020e) = $(rd2 0x02 0x0e)"

echo
echo "=== 3. V4L2 stack (zz_cam_up.sh) ==="
sh /root/zz_cam_up.sh 2>&1 | tail -26

echo
echo "=== 4. exp_max actually in use ==="
cat /sys/module/cam_cap/parameters/exp_max

echo
echo "=== 5. 40 frame stream ==="
nice -n 10 timeout 120 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=40 \
	--stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -2
grep -E '^(avg|stats|ae|awb)' /proc/camcap_info 2>/dev/null | head -4

echo
echo "=== 6. burst 16 (bare arm ceiling, short forced exposure) ==="
echo "burst 16" > /proc/camcap
dmesg | grep 'burst:' | tail -1

echo
echo "=== 7. crash scan (want 0) + load ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace'
cat /proc/loadavg
