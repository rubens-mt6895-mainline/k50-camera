#!/bin/sh
# zz_af_check.sh - the acceptance test for the contrast autofocus.
#
# The desktop camera app restarts on its own and takes /dev/video0 back within
# seconds, which starves any v4l2-ctl run (measured: 5 frames instead of 300),
# so free the device first.  Then open one stream, let the search run, and wait
# (bounded) for it to reach "hold".  The DAC trace in dmesg is the evidence:
# it must peak near the position the manual sweep in zz_af_sweep.sh found.
set -u

pkill -x cheese 2>/dev/null
sleep 2

echo "=== before ==="
grep -E '^(af|ae|stats)' /proc/camcap_info

echo
echo "=== enable the search, stream in the background ==="
echo "af auto" > /proc/camcap
nice -n 10 timeout 240 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=900 \
	--stream-to=/dev/null >/dev/null 2>&1 &
VP=$!
sleep 2

echo
echo "=== wait for the search to settle (max 30 s) ==="
i=0
st=""
while [ "$i" -lt 60 ]; do
	st="$(sed -n 's/^af *:.*state=\([a-z]*\).*/\1/p' /proc/camcap_info | head -1)"
	[ "$st" = "hold" ] && break
	sleep 0.5
	i=$((i + 1))
done
echo "state=$st after $i polls"

echo
echo "=== dmesg: the search trace ==="
dmesg | grep -E 'cam_af|VCM' | tail -40

echo
echo "=== final state ==="
grep -E '^(af|ae|stats|avg|dist)' /proc/camcap_info

kill $VP 2>/dev/null
wait $VP 2>/dev/null

echo
echo "=== crash scan (want 0) ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace'
cat /proc/loadavg
echo "=== zz_af_check done ==="
