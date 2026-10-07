#!/bin/sh
# zz_ae3.sh - reload the module, then watch the AE loop with the settle counter.
set -u

renice -n 19 -p $$ >/dev/null 2>&1

echo "=== reload ==="
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
ls -l /dev/video0
grep -E '^(ae|awb|stats)' /proc/camcap_info

show() {
	grep -E '^(stats|ae|awb)' /proc/camcap_info
}

frames() {
	v4l2-ctl -d /dev/video0 --stream-mmap --stream-count="$1" 2>&1 | tail -1
}

echo
echo "=== dark manual start ==="
v4l2-ctl -d /dev/video0 -c auto_exposure=1 -c exposure_time_absolute=64 \
	-c analogue_gain=256 -c digital_gain=256 2>&1
frames 2
show

echo
echo "=== hand over to the loop, sample as it walks ==="
v4l2-ctl -d /dev/video0 -c auto_exposure=0 2>&1
for n in 15 15 15 30; do
	echo "--- $n more frames ---"
	frames "$n"
	show
done

echo
echo "=== settled?  five samples, five frames apart ==="
for i in 1 2 3 4 5; do
	frames 5
	printf 'sample %d: ' "$i"
	grep -E '^ae' /proc/camcap_info | sed 's/ae *: //'
done

echo
echo "=== dmesg tail ==="
dmesg | grep -i cam_cap | tail -5
