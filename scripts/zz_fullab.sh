#!/bin/sh
# zz_fullab.sh [frames] [threads] - A/B the two full-size (v4l2_bin=1)
# converters on the device, in the two regimes where the conversion is the
# bottleneck:
#
#   custom2       1920x1080 full size  (sensor runs at 120 fps: is the
#                                      converter fast enough to feed it?)
#   normal_video  4000x2256 full size  (was 22 fps with the per-pixel converter;
#                                      does unpacking each row once reach 30?)
#
# v4l2_full_cache=0 selects cam_v4l2_convert_full_ref(), 1 (the default) the
# row-cached cam_v4l2_convert_full_fast().  One device task at a time (m00471):
# the whole sweep runs inside this one ssh session, sequentially.
set -u
NF=${1:-80}
NTH=${2:-8}

for M in custom2 normal_video; do
	for C in 0 1; do
		echo "================ $M  bin 1  v4l2_full_cache=$C ================"
		sh /root/zz_mode.sh "$M" "$NF" "$NTH" 1 1 "v4l2_full_cache=$C"
		mv -f "/root/mode_${M}_b1.yuyv" "/root/ab_${M}_cache${C}.yuyv" 2>/dev/null
	done
done

echo "--- frames kept for the local check ---"
ls -l /root/ab_*.yuyv 2>/dev/null
echo "--- crash counter (want 0) ---"
dmesg | grep -icE 'oops|BUG:|panic|Call trace'
uptime
echo "### zz_fullab done"
