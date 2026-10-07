#!/bin/sh
# zz_ae6.sh - reload the fresh module and run the full AE/AWB acceptance test.
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

P=/sys/module/cam_cap/parameters

show() {
	grep -E '^(stats|ae|awb)' /proc/camcap_info
}

keys() {
	grep -E '^ae' /proc/camcap_info | sed 's/ae *: //'
}

frames() {
	v4l2-ctl -d /dev/video0 --stream-mmap --stream-count="$1" 2>&1 | tail -1
}

echo "=== 1. manual dark start ==="
v4l2-ctl -d /dev/video0 -c auto_exposure=1 -c exposure_time_absolute=64 \
	-c analogue_gain=256 -c digital_gain=256 >/dev/null 2>&1
frames 2
show

echo
echo "=== 2. hand the exposure to the loop ==="
v4l2-ctl -d /dev/video0 -c auto_exposure=0 >/dev/null 2>&1
for n in 10 20 40; do
	echo "--- $n more frames ---"
	frames "$n"
	show
done

echo
echo "=== 3. settled?  five samples, ten frames apart ==="
for i in 1 2 3 4 5; do
	frames 10
	printf 'sample %d: ' "$i"
	keys
done

echo
echo "=== 4. retarget through the module parameter ==="
for t in 1800 700 1200; do
	echo "--- ae_target=$t ---"
	echo "$t" > "$P/ae_target"
	frames 40
	show
done

echo
echo "=== 5. AWB off, fixed gains, then back on ==="
v4l2-ctl -d /dev/video0 -c white_balance_automatic=0 -c red_balance=256 \
	-c blue_balance=256 >/dev/null 2>&1
frames 3
show
v4l2-ctl -d /dev/video0 -c white_balance_automatic=1 >/dev/null 2>&1
for n in 5 15; do
	echo "--- $n more frames ---"
	frames "$n"
	show
done

echo
echo "=== 6. controls as userspace sees them ==="
v4l2-ctl -d /dev/video0 --list-ctrls 2>&1 | grep -E 'exposure|balance|gain|brightness|contrast|saturation'

echo
echo "=== 7. save one frame from the settled state ==="
rm -f /root/v4l2_ae.yuyv
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 \
	--stream-to=/root/v4l2_ae.yuyv 2>&1 | tail -1
ls -l /root/v4l2_ae.yuyv
show
