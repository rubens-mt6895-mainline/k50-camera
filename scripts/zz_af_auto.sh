#!/bin/sh
# zz_af_auto.sh - hand the lens to the driver's contrast search and report what
# it picks.  Run after zz_af_sweep.sh has shown where the module actually
# focuses: the search is only worth trusting once the curve has a clear peak.
set -u

echo "=== before ==="
grep -E '^af' /proc/camcap_info

echo
echo "=== enable the search ==="
echo "af auto" > /proc/camcap
grep -E '^af' /proc/camcap_info

echo
echo "=== 300 frames, one stream, so a full sweep fits ==="
nice -n 10 timeout 180 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=300 \
	--stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1

echo
echo "=== dmesg: the sweep ==="
dmesg | grep -E 'cam_af' | tail -40

echo
echo "=== final state ==="
grep -E '^(af|ae|stats|avg|dist)' /proc/camcap_info

echo
echo "=== crash scan (want 0) ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace'
cat /proc/loadavg
echo "=== zz_af_auto done ==="
