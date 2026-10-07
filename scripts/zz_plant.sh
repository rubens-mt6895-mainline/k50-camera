#!/bin/sh
# zz_plant.sh - step response of the sensor at the operating point the AE
# actually drives it to (integration time pinned at the 0x3000 ceiling), with
# the AE loop switched off so nothing moves except what this script sets.
set -u

renice -n 19 -p $$ >/dev/null 2>&1

show() {
	grep -E '^(stats|ae)' /proc/camcap_info | tr '\n' '|'
	echo
}

frames() {
	v4l2-ctl -d /dev/video0 --stream-mmap --stream-count="$1" 2>&1 | tail -1
}

# manual mode: the governor stops touching the sensor
v4l2-ctl -d /dev/video0 -c auto_exposure=1 2>&1
v4l2-ctl -d /dev/video0 -c exposure_time_absolute=12288 -c digital_gain=1024 2>&1

echo "=== analogue gain sweep at exp=0x3000 dgain=0x0400 ==="
for a in 0x2ad 0x2c0 0x2e0 0x300 0x310 0x320 0x340 0x360 0x380 0x39a 0x3a0 0x3b0 0x3c0; do
	printf 'again=0x%04x ' "$a"
	v4l2-ctl -d /dev/video0 -c analogue_gain="$a" >/dev/null 2>&1
	frames 4
	show
done

echo
echo "=== digital gain sweep at exp=0x3000 again=0x0300 ==="
v4l2-ctl -d /dev/video0 -c analogue_gain=768 >/dev/null 2>&1
for d in 0x0040 0x0080 0x0100 0x0155 0x0200 0x0300 0x0400 0x0600 0x0800 0x0c00 0x1000; do
	printf 'dgain=0x%04x ' "$d"
	v4l2-ctl -d /dev/video0 -c digital_gain="$d" >/dev/null 2>&1
	frames 4
	show
done

echo
echo "=== exposure sweep at again=0x0300 dgain=0x0200 (is it still linear?) ==="
v4l2-ctl -d /dev/video0 -c digital_gain=512 >/dev/null 2>&1
for e in 0x0300 0x0600 0x0c00 0x1800 0x2000 0x2800 0x3000; do
	printf 'exp=0x%04x ' "$e"
	v4l2-ctl -d /dev/video0 -c exposure_time_absolute="$e" >/dev/null 2>&1
	frames 4
	show
done

echo
echo "=== back to auto ==="
v4l2-ctl -d /dev/video0 -c auto_exposure=0 2>&1
frames 30
show
