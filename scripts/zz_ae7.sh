#!/bin/sh
# zz_ae7.sh - reload the gated build: the loop must still close, quietly.
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

cat /sys/module/cam_cap/parameters/ae_trace

frames() {
	v4l2-ctl -d /dev/video0 --stream-mmap --stream-count="$1" 2>&1 | tail -1
}

v4l2-ctl -d /dev/video0 -c auto_exposure=1 -c exposure_time_absolute=64 \
	-c analogue_gain=256 -c digital_gain=256 >/dev/null 2>&1
frames 2
v4l2-ctl -d /dev/video0 -c auto_exposure=0 >/dev/null 2>&1

for i in 1 2 3; do
	frames 40
	printf 'after %3d frames: ' $((i * 40))
	grep -E '^ae' /proc/camcap_info | sed 's/ae *: //'
done

echo
echo "cam_ae trace lines: $(dmesg | grep -c cam_ae)"
echo "cam_cap dmesg tail:"
dmesg | grep cam_cap | tail -4
