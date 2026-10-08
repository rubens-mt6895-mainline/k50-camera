#!/bin/sh
# zz_burst.sh <variant> [frames] - per-frame arm history for custom3 (4000x2256@60)
# so the local analyser can see whether the >=58 ms stalls are periodic.
#
#   variant a: conv_threads 8, pipe_slots 3, sync_parallel 1, --stream-mmap=8
#   variant b: conv_threads 8, pipe_slots 4, sync_parallel 1, --stream-mmap=8
#   variant c: conv_threads 8, pipe_slots 3, sync_parallel 0, --stream-mmap=8
#   variant d: conv_threads 8, pipe_slots 3, sync_parallel 1, --stream-mmap=4
set -u
VAR=${1:-a}
NF=${2:-600}
MW=4000
MH=2256
MVTS=2560
OW=2000
OH=1128
MSTRIDE=$((MW * 3 / 2))
MFRAME=$(( (MSTRIDE * MH + 1048575) / 1048576 * 1048576 ))
EMAX=$((MVTS - 128))
case "$VAR" in
a) NTH=8; PS=3; SP=1; MM=8 ;;
b) NTH=8; PS=4; SP=1; MM=8 ;;
c) NTH=8; PS=3; SP=0; MM=8 ;;
d) NTH=8; PS=3; SP=1; MM=4 ;;
*) echo "unknown variant $VAR"; exit 2 ;;
esac
OUT=/root/burst_$VAR.txt

echo "### zz_burst $VAR: custom3 ${MW}x${MH} -> ${OW}x${OH} buffer $MFRAME vts $MVTS exp_max $EMAX"
echo "### conv_threads=$NTH pipe_slots=$PS sync_parallel=$SP --stream-mmap=$MM frames=$NF"
date

echo "--- 0. free the camera"
pkill -x cheese 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 0.5
if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap 2>&1 | sed 's/^/  /'
fi
grep -q '^cam_cap ' /proc/modules && { echo "  [!!] cam_cap still loaded, ABORT"; exit 1; }

echo "--- 1. custom3 bring-up"
IMX582_MODE=custom3 MODE_W=$MW MODE_H=$MH MODE_STRIDE=$MSTRIDE MODE_FRAME=$MFRAME \
	sh /root/zz_v80.sh 2>&1 | tail -6

echo "--- 2. V4L2 stack"
CAM_CAP_PARAMS="exp_hsize=$MW exp_vsize=$MH out_width=$OW out_height=$OH exp_max=$EMAX conv_threads=$NTH v4l2_bin=2 arm_trace=1 pipe_slots=$PS sync_parallel=$SP" \
	sh /root/zz_cam_up.sh 2>&1 | tail -8

dmesg -c >/dev/null 2>&1
echo "--- 3. stream $NF frames (+ $MM mmap buffers)"
S=$(date +%s%N)
nice -n 10 timeout 120 v4l2-ctl --stream-mmap=$MM --stream-count=$NF --stream-to=/dev/null 2>&1 | tail -3
E=$(date +%s%N)
echo "--- 4. info"
grep -E '^(avg|timing|dist|stats)' /proc/camcap_info 2>/dev/null
echo "--- 5. arm history"
dmesg | grep -E 'arm seq=' >$OUT
echo "  lines: $(wc -l <$OUT)  ($OUT)"
grep -c 'FRAME READY' $OUT | sed 's/^/  frame ready: /'
grep -c 'TIMEOUT' $OUT | sed 's/^/  timeouts   : /'
echo "  wall: $(( (E - S) / 1000000 )) ms for $NF frames"
echo "--- 6. health"
echo "  crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog|Unable to handle')"
rmmod cam_cap 2>/dev/null || echo "  [!!] rmmod failed"
echo "### zz_burst $VAR done"
