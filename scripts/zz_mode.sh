#!/bin/sh
# zz_mode.sh <mode> [frames] [threads] [bin] [nc] [extra-params] - bring the
# whole camera stack up in ONE vendor IMX582 sensor mode and measure what that
# mode actually does.
#
#   preview(4000x3000) normal_video(4000x2256) custom3(4000x2256@60)
#   custom2(1920x1080@120) hs_video(1920x1080@240) custom4(8000x6000)
#   custom5(4000x3000 1:1 crop)
#
# bin 2 (default) halves the sensor mode into YUYV; bin 1 keeps every raw pixel
# and runs the full-size bilinear converter, which is only correct for the
# binned sensor modes (0x0900=1) - i.e. everything except custom4/custom5.
#
# extra-params is appended to the insmod parameter list verbatim, for the
# experiments that do not deserve their own script, e.g.
#   sh zz_mode.sh custom2 100 8 1 4 v4l2_full_cache=0
#
# The mode tables come from src/rubensimx582_Sensor.h by way of
# scripts/gen_mode_table.py; zz_ctrl_run.sh pushes them as /root/mode_<name>.txt.
# One device task at a time (m00471): measure, print, leave the camera idle.
set -u
MODE=${1:-preview}
NF=${2:-40}
NTH=${3:-6}
BIN=${4:-2}
case "$BIN" in 1|2) ;; *) echo "bin must be 1 or 2"; exit 2 ;; esac
# Frames written to /root for the local check: a bin 1 4000x3000 frame is 24 MB,
# so the caller can ask for one only.  nc=0 means "do not dump anything" - it is
# NOT passed to v4l2-ctl, where --stream-count=0 means "stream forever" (one such
# slip wrote 122 GB in 11 minutes).
NC=${5:-4}
case "$NC" in
  0) ;;
  *[!0-9]*|'') NC=4 ;;
esac
EXTRA=${6:-}

# geometry, plus the mode's own VTS: the exposure ceiling has to stay below it
# or the sensor stretches the frame period (the old 9 fps failure at VTS 3658).
# preview keeps the built-in table with the tuned VTS 3300 (33.5 fps ceiling).
case "$MODE" in
  preview)      MW=4000; MH=3000; MVTS=3300 ;;
  normal_video) MW=4000; MH=2256; MVTS=3658 ;;
  custom3)      MW=4000; MH=2256; MVTS=2560 ;;
  custom2)      MW=1920; MH=1080; MVTS=2100 ;;
  hs_video)     MW=1920; MH=1080; MVTS=1236 ;;
  custom4)      MW=8000; MH=6000; MVTS=6271 ;;
  custom5)      MW=4000; MH=3000; MVTS=3135 ;;
  *) echo "unknown mode '$MODE'"; \
     echo "expected: preview normal_video custom3 custom2 hs_video custom4 custom5"; exit 2 ;;
esac
OW=$((MW / BIN))
OH=$((MH / BIN))
MSTRIDE=$((MW * 3 / 2))
MFRAME=$(( (MSTRIDE * MH + 1048575) / 1048576 * 1048576 ))
EMAX=$((MVTS - 128))
FR=/root/mode_${MODE}_b${BIN}.yuyv
if [ "$MODE" = preview ]; then export IMX582_MODE=""; else export IMX582_MODE="$MODE"; fi

echo "### zz_mode: $MODE  ${MW}x${MH} -> ${OW}x${OH} (bin $BIN)  stride $MSTRIDE  buffer $MFRAME  vts $MVTS  exp_max $EMAX${EXTRA:+  extra: $EXTRA}"

echo "--- 0. free the camera ---"
pgrep -x cheese >/dev/null 2>&1 && { pkill -x cheese; sleep 2; }
fuser -k /dev/video0 2>/dev/null
sleep 0.5

echo "--- 1. clean module state ---"
if grep -q '^cam_cap ' /proc/modules; then
  rmmod cam_cap 2>&1 | sed 's/^/  /'
fi
if grep -q '^cam_cap ' /proc/modules; then echo "  [!!] cam_cap still loaded, ABORT"; exit 1; fi
echo "  [ok] cam_cap not loaded"

echo "--- 2. sensor bring-up + ${MODE} table replay (zz_v80.sh) ---"
MODE_W=$MW MODE_H=$MH MODE_STRIDE=$MSTRIDE MODE_FRAME=$MFRAME sh /root/zz_v80.sh 2>&1 | tail -30

echo "--- 3. V4L2 stack in the same mode ---"
CAM_CAP_PARAMS="exp_hsize=$MW exp_vsize=$MH out_width=$OW out_height=$OH exp_max=$EMAX conv_threads=$NTH v4l2_bin=$BIN $EXTRA" \
  sh /root/zz_cam_up.sh 2>&1 | tail -32

echo "--- 4. real fps over $NF frames ---"
nice -n 10 v4l2-ctl --stream-mmap --stream-count=$NF --stream-to=/dev/null 2>&1 \
  | grep -oE '[0-9]+\.[0-9]+ fps' | tail -2
grep -E '^(avg|stats|ae|awb|dist)' /proc/camcap_info 2>/dev/null

echo "--- 5. bare arm ceiling (no conversion) ---"
echo "burst 8" > /proc/camcap 2>/dev/null
sleep 6
dmesg | grep -E 'burst:' | tail -2

if [ "$NC" -gt 0 ]; then
	echo "--- 6. $NC frame(s) on disk for a local geometry/colour check ---"
	nice -n 10 v4l2-ctl --stream-mmap --stream-count=$NC --stream-to=$FR >/dev/null 2>&1
	ls -l $FR 2>/dev/null
	echo "  expect $((OW * OH * 2)) bytes/frame"
else
	echo "--- 6. no frame dump requested (nc=0) ---"
fi

echo "--- 7. dmesg tail + health ---"
dmesg | tail -6
uptime
echo "### zz_mode $MODE done"
