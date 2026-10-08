#!/bin/sh
# zz_afnoise.sh - do the focus search and the wobble run on a scene nobody
# touches?
#
# The user's complaint is "occasionally it focuses very often, and it misfocuses
# even though my hand has not moved".  In a still scene the only thing that
# moves is the AE (and the flicker it fights), and the old re-scan test compared
# the live metric against the *scan's* best metric, which was measured at an
# older exposure -- a dip in the normalised metric then looked like a scene
# change.  This script streams a static scene with af_floor=0 (so no frame is
# ever dismissed as "too flat to judge") and reports how many scans and wobbles
# the search starts over the window.
#
# usage: sh /root/zz_afnoise.sh <ko-to-test> <label> [seconds]
set -u
KO_SRC=$1
LABEL=$2
SECS=${3:-90}

echo "=== zz_afnoise: $LABEL ==="
date
cp -f "$KO_SRC" /root/cam_cap.ko || { echo "cannot install $KO_SRC"; exit 1; }
md5sum /root/cam_cap.ko

# the sensor power rails and the MCLK come from zz_v80.sh; without them the VCM
# probe fails and the search never runs at all (af line: "not ready")
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh >/tmp/v80.log 2>&1
tail -3 /tmp/v80.log
CAM_CAP_PARAMS="af_floor=0 af_trace=1" sh /root/zz_cam_up.sh 2>&1 | tail -4
grep -E '^af ' /proc/camcap_info || grep -E '^af' /proc/camcap_info

echo "--- streaming ${SECS}s of a static scene (nobody touches the phone)"
nice -n 19 timeout $((SECS + 30)) v4l2-ctl -d /dev/video0 --stream-mmap \
	--stream-count=$((SECS * 33)) --stream-to=/dev/null >/tmp/af_noise.log 2>&1 &
SPID=$!
sleep 10
A=$(grep -E '^af' /proc/camcap_info)
echo "t=10s  $A"
sleep $((SECS - 10))
B=$(grep -E '^af' /proc/camcap_info)
echo "t=${SECS}s  $B"
wait $SPID 2>/dev/null

# pull the counters out of both samples and show the deltas
get() { echo "$1" | sed 's/.*'"$2"'=\([0-9]*\).*/\1/'; }
for K in scans wobbles low; do
	VA=$(get "$A" "$K")
	VB=$(get "$B" "$K")
	echo "  $K: $VA -> $VB  (delta $((VB - VA)))"
done
echo "--- af trace lines (last 12)"
dmesg | grep 'cam_af:' | tail -12
echo "--- crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog|Unable to handle')"
rmmod cam_cap 2>/dev/null
echo "=== done $LABEL ==="
