#!/bin/sh
# zz_af_wobble.sh [n] - run the contrast search, then force n tracking wobbles.
#
# A wobble re-measures the held position and one step either side; the lens only
# moves if a neighbour wins by more than CAMCAP_AF_WOBBLE_GAIN_PCT, which is what
# keeps a flat (textureless) scene from walking the lens on noise.  The point of
# this script is to see the three metrics and the decision, so it prints the af
# line after each one plus the kernel trace.
set -u
N="${1:-3}"

pkill -x cheese 2>/dev/null
sleep 2

echo "=== before ==="
grep -E '^(af|ae|stats)' /proc/camcap_info

nice -n 10 timeout 300 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1200 \
	--stream-to=/dev/null >/dev/null 2>&1 &
VP=$!
sleep 1
echo "af auto" > /proc/camcap

i=0
st=""
while [ "$i" -lt 120 ]; do
	st="$(sed -n 's/^af *:.*state=\([a-z]*\).*/\1/p' /proc/camcap_info | head -1)"
	[ "$st" = "hold" ] && break
	i=$((i + 1))
	sleep 0.5
done
echo
echo "=== search finished after $i polls, state=$st ==="
grep -E '^af' /proc/camcap_info

k=1
while [ "$k" -le "$N" ]; do
	echo "af wobble" > /proc/camcap
	sleep 2
	echo
	echo "--- wobble $k ---"
	grep -E '^af' /proc/camcap_info
	k=$((k + 1))
done

echo
echo "=== kernel trace ==="
dmesg | grep -E 'cam_af' | tail -40

echo
echo "=== final ==="
grep -E '^(af|ae|stats|avg|dist)' /proc/camcap_info
kill $VP 2>/dev/null
wait $VP 2>/dev/null
echo "=== zz_af_wobble done ==="
