#!/bin/sh
# cam_boot.sh - bring the IMX582 camera up from a cold boot (idempotent, bounded).
#
# Installed at /root/cam_boot.sh and run by cam-camera.service (Type=oneshot,
# After=multi-user.target) so that /dev/video0 exists with no manual ssh work.
#
#   1. wait for the pieces the vendor bring-up needs (debugfs pinctrl, i2c-10/11)
#   2. drop any stale holder of /dev/video0 (a leftover stream makes the reload fail)
#   3. zz_v80.sh     -> sensor rails/MCLK/LDO/reset/DPHY/CSI2 + IMX582 init
#   4. zz_cam_up.sh  -> V4L2 base modules + cam_cap (v4l2_enable=1)
#
# Everything is logged to /var/log/cam_boot.log.  Failure is non-fatal: the
# desktop comes up regardless, and `sh /root/cam_reset.sh` retries by hand.

LOG=/var/log/cam_boot.log
exec >>"$LOG" 2>&1
echo "================ $(date) cam_boot start"
echo "--- kernel: $(uname -r)   uptime:$(uptime | sed 's/.*up//;s/,.*//')"

echo "--- 1. wait for prerequisites"
i=0
while [ $i -lt 60 ]; do
	[ -d /sys/kernel/debug/pinctrl ] && [ -c /dev/i2c-10 ] && [ -c /dev/i2c-11 ] && break
	i=$((i + 1))
	sleep 0.5
done
[ -d /sys/kernel/debug/pinctrl ] || echo "    warn: pinctrl debugfs missing"
[ -c /dev/i2c-10 ] || echo "    warn: /dev/i2c-10 missing"
[ -c /dev/i2c-11 ] || echo "    warn: /dev/i2c-11 missing"

echo "--- 2. release /dev/video0"
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

echo "--- 3. sensor bring-up (zz_v80.sh)"
sh /root/zz_v80.sh
echo "    zz_v80 rc=$?"

echo "--- 4. V4L2 stack (zz_cam_up.sh)"
sh /root/zz_cam_up.sh
echo "    zz_cam_up rc=$?"

if [ -c /dev/video0 ]; then
	echo "RESULT: ok  /dev/video0 $(cat /sys/class/video4linux/video0/name 2>/dev/null)"
	echo "        camera software: sh /root/zz_cam_app.sh   (or just run Cheese)"
else
	echo "RESULT: FAILED - no /dev/video0; try: sh /root/cam_reset.sh --full"
fi
echo "================ $(date) cam_boot end"
