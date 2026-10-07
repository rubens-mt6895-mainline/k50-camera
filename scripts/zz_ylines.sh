#!/bin/sh
# zz_ylines.sh - arm latency vs number of captured lines, in the live sensor mode.
# If the time is proportional to the line count the sensor sets the pace; if short
# captures come back much faster than linearly, the tail of the DMA is the limit.
for y in 2256 1128 564 282; do
	echo "cfg 1 0 4000 0 $y 6000 $y 6000" > /proc/camcap
	dmesg -c >/dev/null 2>&1
	echo "burst 8" > /proc/camcap
	sleep 5
	printf "ysize %4d : %s\n" "$y" "$(dmesg | grep -oE 'burst: .*ceiling' | tail -1)"
done
# leave the DMA window the way the driver expects it
echo "cfg 1 0 4000 0 2256 6000 2256 6000" > /proc/camcap
echo "=== zz_ylines done ==="
