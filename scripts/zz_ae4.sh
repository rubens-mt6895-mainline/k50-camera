#!/bin/sh
# zz_ae4.sh - reload, hand exposure to the loop, then dump the AE's own trace.
set -u

renice -n 19 -p $$ >/dev/null 2>&1

pkill -x cheese 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>/dev/null
if ! insmod /root/cam_cap.ko v4l2_enable=1; then
	echo "INSMOD FAILED"
	dmesg | tail -8
	exit 1
fi
i=0
while [ $i -lt 12 ]; do
	[ -c /dev/video0 ] && break
	sleep 0.5
	i=$((i + 1))
done

grep -E '^(ae|awb)' /proc/camcap_info

frames() {
	v4l2-ctl -d /dev/video0 --stream-mmap --stream-count="$1" 2>&1 | tail -1
}

echo "=== dark manual start ==="
v4l2-ctl -d /dev/video0 -c auto_exposure=1 -c exposure_time_absolute=64 \
	-c analogue_gain=256 -c digital_gain=256 >/dev/null 2>&1
frames 2
grep -E '^(stats|ae)' /proc/camcap_info

echo "=== hand over, 30 frames ==="
v4l2-ctl -d /dev/video0 -c auto_exposure=0 >/dev/null 2>&1
frames 30
grep -E '^(stats|ae)' /proc/camcap_info

echo "=== 30 more ==="
frames 30
grep -E '^(stats|ae)' /proc/camcap_info

echo
echo "=== cam_ae trace ==="
dmesg | grep cam_ae | tail -40
