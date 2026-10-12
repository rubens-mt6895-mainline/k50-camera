#!/bin/sh
# cam_boot.sh - bring all FOUR cameras up from a cold boot (idempotent, bounded).
#
# Installed at /root/cam_boot.sh and run by cam-camera.service (Type=oneshot,
# After=multi-user.target) so that /dev/video0..3 work with no manual ssh work.
#
#   1. wait for the pieces the vendor bring-up needs (debugfs pinctrl, i2c-10/11)
#   2. drop any stale holders of the video nodes (a leftover stream makes the
#      module reload fail with "Module cam_cap is in use")
#   3. zz_v80.sh     -> sensor rails/MCLK/LDO/reset/DPHY/CSI2 + IMX582 init
#   4. zz_cam_up.sh  -> V4L2 base modules + cam_cap (v4l2_enable=1 cam_nodes=4),
#      i.e. /dev/video0..3, so a camera app can pick any of the four
#   5. zz_aux_up.sh  -> the three auxiliary cameras are userspace bring-up (the
#      driver has no sensor driver for them): rails, MCLK, reset, register
#      tables, D-PHY.  Critically this runs *after* step 3, because the main
#      camera's bring-up writes fan53870 0x03 = 0x60 (LDO6|LDO7 only) and that
#      cuts the power of the auxiliary modules - which is why switching to them
#      used to give a flat green frame (YUV 0,0,0 from a zero-filled buffer).
#      The union mask 0x7f keeps all four powered.
#
#   6. zz_cam_main.sh -> select the main board again: the verification in step 5
#      streams each auxiliary node, so the engine ends up on the last of them
#      and node 0 stays -EBUSY until userspace picks the main board (2026-10-09).
#
# Failure is non-fatal: the desktop comes up regardless, /dev/video0 keeps
# working when the auxiliary part fails, and `sh /root/cam_reset.sh` retries by
# hand.  Everything is logged to /var/log/cam_boot.log.
#
# Switching back: after an auxiliary camera has streamed, the driver refuses
# node 0 until userspace selects the main board again (2026-10-09 lesson), so
# `sh /root/zz_cam_main.sh` (or the 切回主摄 launcher) is the way back.

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

echo "--- 2. release the video nodes"
for a in cheese guvcview kamoso snapshot; do
	pkill -x "$a" 2>/dev/null && echo "    stopped $a"
done
sleep 1
fuser -k /dev/video0 /dev/video1 /dev/video2 /dev/video3 2>/dev/null
sleep 1

echo "--- 3. sensor bring-up (zz_v80.sh, no module load)"
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh
echo "    zz_v80 rc=$?"

echo "--- 4. V4L2 stack, four nodes (zz_cam_up.sh cam_nodes=4)"
CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh
echo "    zz_cam_up rc=$?"
ls -l /dev/video* 2>&1

if [ ! -c /dev/video1 ]; then
	echo "    four-node load failed - retrying once after a harder release"
	for a in cheese guvcview kamoso snapshot; do pkill -9 -x "$a" 2>/dev/null; done
	fuser -k /dev/video0 /dev/video1 /dev/video2 /dev/video3 2>/dev/null
	sleep 2
	CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh
	echo "    zz_cam_up rc=$? (retry)"
fi

if [ -c /dev/video1 ]; then
	echo "--- 5. auxiliary cameras (zz_aux_up.sh)"
	sh /root/zz_aux_up.sh
	echo "    zz_aux_up rc=$?"
	echo "--- 5b. hand the engine back to the main camera"
	# zz_aux_up.sh verifies the three auxiliary nodes by streaming them, which
	# leaves the engine on the last one; node 0 refuses to start until userspace
	# selects the main board again (2026-10-09 lesson).
	sh /root/zz_cam_main.sh
	echo "    zz_cam_main rc=$?"
else
	echo "--- 5. skipped: the module came up single-node"
fi

echo "--- 6. result"
if [ -c /dev/video0 ]; then
	echo "RESULT: ok  /dev/video0 $(cat /sys/class/video4linux/video0/name 2>/dev/null)"
	echo "        nodes: $(ls /dev/video* 2>/dev/null | tr '\n' ' ')"
	echo "        camera software: sh /root/zz_cam_app.sh   (or just run Cheese/Kamoso)"
	echo "        switch back to the main camera: sh /root/zz_cam_main.sh"
else
	echo "RESULT: FAILED - no /dev/video0; try: sh /root/cam_reset.sh --full"
fi
echo "================ $(date) cam_boot end"
