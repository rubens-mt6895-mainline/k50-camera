#!/bin/sh
# cam_reset.sh - one-click camera recovery.
#
#   sh /root/cam_reset.sh          fast path: reload the V4L2 stack (sensor already up)
#   sh /root/cam_reset.sh --full   also redo the sensor bring-up (after a bad hang/reboot)
#
# Use this when Cheese (or any app) says it cannot connect to the camera: the
# usual cause is a stale process still holding /dev/video0, or the modules gone
# after a reboot.

FULL=0
[ "$1" = "--full" ] && FULL=1
KO=/root/cam_cap.ko

echo "=== camera reset ($([ $FULL = 1 ] && echo full || echo fast)) ==="

echo "--- 1. who is using /dev/video0"
fuser -v /dev/video0 2>&1 | sed 's/^/    /'

echo "--- 2. stop camera applications"
pkill -x cheese 2>/dev/null && echo "    stopped cheese" || echo "    cheese not running"
pkill -x guvcview 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null && echo "    killed remaining holders" || echo "    no remaining holders"
sleep 1

if [ $FULL = 1 ]; then
	echo "--- 3. sensor bring-up (zz_v80.sh)"
	nice -n 19 sh /root/zz_v80.sh
	echo "    rc=$?"
else
	echo "--- 3. sensor bring-up skipped (use --full if the picture is black)"
fi

echo "--- 4. V4L2 stack (zz_cam_up.sh)"
nice -n 19 sh /root/zz_cam_up.sh
rc=$?
echo "    rc=$rc"

echo
if [ -c /dev/video0 ]; then
	echo "=== OK: /dev/video0 ready ==="
	ls -l /dev/video0
	if command -v v4l2-ctl >/dev/null 2>&1; then
		echo "--- 5-frame test"
		timeout 20 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=5 2>&1 | tail -2
	fi
	echo
	echo "start the camera app with:  sh /root/zz_cam_app.sh"
else
	echo "=== FAILED: /dev/video0 missing ==="
	echo "try:  sh /root/cam_reset.sh --full"
	echo "log:  tail -40 /var/log/cam_boot.log"
	exit 1
fi
echo "=== note: $KO is the current driver build ($(ls -l $KO 2>/dev/null | awk '{print $5}') bytes) ==="
