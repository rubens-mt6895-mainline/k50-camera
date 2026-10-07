#!/bin/sh
# zz_period.sh - does the sensor stretch the frame period when the exposure
# reaches VTS?  Manual exposure isolates that from the AE loop, then the AE is
# put back and the steady rate is measured after a settle pause (the earlier
# cold start measured 27.7 fps because the AE walked its exposure straight up
# to the cap).
set -u

pkill -x cheese 2>/dev/null
sleep 0.5
fuser -k /dev/video0 2>/dev/null
sleep 0.5

rd2() { i2ctransfer -y -f 10 w2@0x10 "$1" "$2" r2@0x10 2>&1; }

echo "=== sensor timing registers ==="
echo "  VTS (0x0340) = $(rd2 0x03 0x40)"
echo "  HTS (0x0342) = $(rd2 0x03 0x42)"

echo
echo "=== AE off, exposure sweep (VTS is 3500 lines) ==="
v4l2-ctl -d /dev/video0 -c exposure_auto=1 >/dev/null 2>&1
for e in 0x0dac 0x0d8c 0x0d70 0x0d48 0x0d2c 0x0ce0 0x0380; do
	v4l2-ctl -d /dev/video0 -c exposure_absolute=$((e)) >/dev/null 2>&1
	sleep 1
	rate=$(nice -n 10 timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap \
		--stream-count=20 --stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1)
	printf '  exp=0x%04x (%4u lines): %s | %s\n' "$((e))" "$((e))" "$rate" \
		"$(grep -E '^avg' /proc/camcap_info | head -1)"
done

echo
echo "=== AE back on, settle 4 s, then 60 frames ==="
v4l2-ctl -d /dev/video0 -c exposure_auto=0 >/dev/null 2>&1
sleep 4
nice -n 10 timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=60 \
	--stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1
grep -E '^(avg|stats|ae|awb)' /proc/camcap_info 2>/dev/null | head -4

echo
echo "=== second 60 frames (drift check) ==="
nice -n 10 timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=60 \
	--stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1
grep -E '^(avg|ae)' /proc/camcap_info 2>/dev/null | head -2

echo
echo "=== crash scan (want 0) + load ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace'
cat /proc/loadavg
