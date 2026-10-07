#!/bin/sh
# zz_two.sh - the two 1080p sensor modes at full size, in one device session.
set -u
for spec in "hs_video 40 8 1" "custom2 40 8 1"; do
	# shellcheck disable=SC2086
	set -- $spec
	echo "================ bin 1: $1  ($2 frames, $3 threads, $4 to disk)"
	sh /root/zz_mode.sh "$1" "$2" "$3" 1 "$4" 2>&1
done
echo "### zz_two done"
