#!/bin/sh
# zz_sensor_state.sh - why did the bare-arm rate drop to 9 fps?
#
# The sensor stretches its frame period when the exposure goes past one frame
# worth of lines, so the arm time itself tells us nothing unless we also know
# the exposure.  Read the mode and the exposure straight off the sensor, then
# try to get rid of the process that died inside alloc_contig_pages().
set -u

echo "=== stuck process ==="
ps -e -o pid,stat,etime,comm | grep -E 'v4l2-ctl|COMMAND'
P=$(pgrep -x v4l2-ctl | head -1)
if [ -n "${P:-}" ]; then
	echo "wchan: $(cat /proc/$P/wchan 2>/dev/null)"
	echo "trying kill -9"
	kill -9 "$P" 2>&1
	sleep 2
	ps -p "$P" -o pid,stat,comm 2>&1
fi

echo "=== sensor registers (bus 10, addr 0x10) ==="
for R in 0x0100 0x0101 0x0112 0x0340 0x0342 0x0202 0x0204 0x020e 0x0301 0x0305; do
	V=$(i2ctransfer -y -f 10 w2@0x10 $R r2@0x10 2>&1)
	echo "$R = $V"
done

echo "=== vts/hts -> frame rate ==="
VT=$(i2ctransfer -y -f 10 w2@0x10 0x0340 r2@0x10 2>/dev/null)
HT=$(i2ctransfer -y -f 10 w2@0x10 0x0342 r2@0x10 2>/dev/null)
echo "VTS raw: $VT   HTS raw: $HT"

echo "=== driver + load ==="
grep -E 'ae |awb |timing|buffer_|mapping' /proc/camcap_info
cat /proc/loadavg
