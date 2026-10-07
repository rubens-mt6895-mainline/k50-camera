#!/bin/sh
# zz_ae5.sh - the module is already loaded: does the closed loop stay put?
set -u

renice -n 19 -p $$ >/dev/null 2>&1

frames() {
	v4l2-ctl -d /dev/video0 --stream-mmap --stream-count="$1" 2>&1 | tail -1
}

echo "=== current ==="
grep -E '^(stats|ae|awb)' /proc/camcap_info

for i in 1 2 3 4 5 6; do
	frames 10
	printf 'after %2d frames: ' $((i * 10))
	grep -E '^ae' /proc/camcap_info | sed 's/ae *: //'
done

echo
echo "=== last cam_ae changes ==="
dmesg | grep cam_ae | tail -4

echo
echo "=== retarget to 700, then 1800 ==="
echo 700 > /sys/module/cam_cap/parameters/ae_target
frames 40
grep -E '^(stats|ae)' /proc/camcap_info
echo 1800 > /sys/module/cam_cap/parameters/ae_target
frames 40
grep -E '^(stats|ae)' /proc/camcap_info
echo 1200 > /sys/module/cam_cap/parameters/ae_target
frames 40
grep -E '^(stats|ae)' /proc/camcap_info
