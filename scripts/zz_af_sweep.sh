#!/bin/sh
# zz_af_sweep.sh [positions...] - manual contrast sweep of the VCM.
#
# The focus metric is produced by the frame converter, so a stream has to be
# running for a reading to mean anything.  This opens one v4l2-ctl stream in the
# background (finite count, /dev/null sink: no disk writes), walks the DAC code,
# and prints the mean |dY| of the frames that follow each move.  That curve is
# the honest picture of where this lens module focuses at which current; the
# search in the driver is only worth trusting once the curve has a clear peak.
set -u

POS="${*:-0 64 128 192 256 320 384 448 512 576 640 704 768 832 896 960 1023}"

# The desktop camera app auto-restarts and takes /dev/video0 back within
# seconds, leaving v4l2-ctl with a handful of frames; the sweep must own the
# device for its whole run.
pkill -x cheese 2>/dev/null
sleep 2

echo "=== precondition ==="
grep -E '^(af|stats|ae)' /proc/camcap_info

echo
echo "=== open a stream for the measurement ==="
nice -n 10 timeout 300 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=3000 \
	--stream-to=/dev/null >/dev/null 2>&1 &
VP=$!
sleep 3
grep -E '^(avg|af)' /proc/camcap_info

echo
echo "=== sweep: DAC -> focus metric (mean |dY|, Q8), three samples each ==="
echo "=== ae= and y= are the exposure and mean luma at that sample: they must not move ==="
for p in $POS; do
	echo "af pos $p" > /proc/camcap
	sleep 1.2
	m=""
	for k in 1 2 3; do
		m="$m$(sed -n 's/^af *:.*metric=\([0-9]*\).*/\1/p' /proc/camcap_info | head -1) "
		sleep 0.4
	done
	a="$(sed -n 's/^ae *:.*exp=\(0x[0-9a-f]*\) again=\(0x[0-9a-f]*\).*/\1+\2/p' /proc/camcap_info | head -1)"
	y="$(sed -n 's/^af *:.* y=\([0-9]*\).*/\1/p' /proc/camcap_info | head -1)"
	printf '  pos=%4s  metric %s ae=%s y=%s\n' "$p" "$m" "$a" "$y"
done

echo
echo "=== af state after the sweep ==="
grep -E '^(af|ae|stats|avg)' /proc/camcap_info
kill $VP 2>/dev/null
wait $VP 2>/dev/null
echo "=== zz_af_sweep done ==="
