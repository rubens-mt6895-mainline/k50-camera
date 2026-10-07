#!/bin/sh
# zz_full2.sh [frames] [threads] - finish the full-size (v4l2_bin=1) table for
# the two modes the first sweep did not cover, with the row-cached converter:
#
#   preview    4000x3000 full size   (per-pixel converter measured 19.4 fps)
#   hs_video   1920x1080 full size   (sensor at 240 fps, arm only 4.6 ms)
#
# Also drops the earlier frame dumps so /root does not fill up with 24 MB
# files.  One device task at a time (m00471).
set -u
NF=${1:-60}
NTH=${2:-8}

rm -f /root/mode_preview_b1.yuyv /root/mode_normal_video_b1.yuyv \
      /root/mode_custom2_b1.yuyv /root/mode_hs_video_b1.yuyv

for M in preview hs_video; do
	echo "================ $M  bin 1  v4l2_full_cache=1 ================"
	sh /root/zz_mode.sh "$M" "$NF" "$NTH" 1 1 "v4l2_full_cache=1"
done

echo "--- disk after the sweep ---"
df -h /root | tail -1
ls -l /root/mode_*_b1.yuyv 2>/dev/null
echo "--- crash counter (want 0) ---"
dmesg | grep -icE 'oops|BUG:|panic|Call trace'
uptime
echo "### zz_full2 done"
