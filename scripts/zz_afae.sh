#!/bin/sh
# zz_afae.sh - move the *exposure* while the scene stays put, which is exactly
# the condition the user described ("it misfocuses even though my hand has not
# moved").
#
# The old re-scan test compared the live metric against the metric the scan
# winner recorded at an older exposure; an AE step then reads as a scene change.
# The new build compares against a slow average taken at the position being
# held.  This script swings ae_target between 200 and 4000 every 6 s (the AE
# ladder then drives exposure and gain up and down) and counts how many full
# re-scans each module starts.
#
# usage: sh /root/zz_afae.sh <ko-to-test> <label> [cycles] [dark-target] [bright-target]
set -u
KO_SRC=$1
LABEL=$2
CYCLES=${3:-8}
# ae_target is on the 0..1000 scale of the AE's own measurement.  A dim room
# measured ~59, so a target above that only ever asks for *more* light (already
# at the ceiling) -- the low target has to sit below it to swing the exposure.
TLOW=${4:-30}
THIGH=${5:-4000}

echo "=== zz_afae: $LABEL ==="
date
cp -f "$KO_SRC" /root/cam_cap.ko || { echo "cannot install $KO_SRC"; exit 1; }
md5sum /root/cam_cap.ko

CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh >/tmp/v80.log 2>&1
tail -2 /tmp/v80.log
CAM_CAP_PARAMS="af_floor=0 af_trace=1" sh /root/zz_cam_up.sh 2>&1 | tail -3
grep -E '^af' /proc/camcap_info
dmesg -c >/dev/null 2>&1	# fresh trace + crash window for this leg

nice -n 19 timeout $((CYCLES * 12 + 60)) v4l2-ctl -d /dev/video0 --stream-mmap \
	--stream-count=$((CYCLES * 12 * 33 + 900)) --stream-to=/dev/null \
	>/tmp/af_ae.log 2>&1 &
SPID=$!
sleep 10
A=$(grep -E '^af' /proc/camcap_info)
echo "start  $A"

i=0
while [ $i -lt $CYCLES ]; do
	echo $THIGH >/sys/module/cam_cap/parameters/ae_target 2>/dev/null
	sleep 6
	echo "  cycle $i bright: $(grep -E '^ae' /proc/camcap_info)"
	echo $TLOW >/sys/module/cam_cap/parameters/ae_target 2>/dev/null
	sleep 6
	echo "  cycle $i dark  : $(grep -E '^ae' /proc/camcap_info)"
	i=$((i + 1))
	echo "         af: $(grep -E '^af' /proc/camcap_info)"
done
echo $THIGH >/sys/module/cam_cap/parameters/ae_target 2>/dev/null
sleep 2

B=$(grep -E '^af' /proc/camcap_info)
echo "end    $B"
wait $SPID 2>/dev/null

get() { echo "$1" | sed 's/.*'"$2"'=\([0-9]*\).*/\1/'; }
for K in scans wobbles; do
	VA=$(get "$A" "$K")
	VB=$(get "$B" "$K")
	echo "  $K: $VA -> $VB  (delta $((VB - VA)))"
done
echo "--- scan point measurements in this leg's trace (coarse+fine; a re-scan adds a burst)"
dmesg | grep -c 'cam_af: \(coarse\|fine\)'
echo "--- af trace tail"
dmesg | grep 'cam_af:' | tail -6
echo "--- crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog|Unable to handle')"
rmmod cam_cap 2>/dev/null
echo "=== done $LABEL ==="
