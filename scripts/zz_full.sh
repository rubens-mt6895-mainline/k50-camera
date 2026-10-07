#!/bin/sh
# zz_full.sh - sweep the full-size (v4l2_bin=1) output path across every sensor
# mode that can carry it, inside ONE device session (one device task at a time,
# m00471).  Each line is "<mode> <frames> <threads> <frames-on-disk>".
#
# The binned modes (0x0900=1) hand out one sample per logical Bayer pixel, so
# bin 1 turns them into their real, un-halved resolution:
#   hs_video     1920x1080 sensor @240 -> real 1920x1080
#   custom2      1920x1080 sensor @120 -> real 1920x1080
#   normal_video 4000x2256  sensor @30  -> real 4000x2256
#   preview      4000x3000  sensor @30  -> real 4000x3000 (still frames)
# custom4/custom5 are unbinned (Bayer period 2) and must stay on bin 2.
set -u
for spec in "hs_video 40 8 2" "custom2 40 8 2" "normal_video 16 8 1" "preview 10 8 1"; do
	# shellcheck disable=SC2086
	set -- $spec
	echo "================ bin 1: $1  ($2 frames, $3 threads, $4 to disk)"
	sh /root/zz_mode.sh "$1" "$2" "$3" 1 "$4" 2>&1
done
echo "### zz_full done"
