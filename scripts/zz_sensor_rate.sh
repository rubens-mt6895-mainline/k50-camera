#!/bin/sh
# Is the frame period set by our pipeline, by the exposure, or by the sensor?
# AE off, gains fixed, sweep the integration time; then count CSI2 packets per
# captured frame to see whether the sensor free-runs faster than we capture.
exec 2>&1
renice -n 10 -p $$ >/dev/null 2>&1
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
if lsmod | grep -q '^cam_cap '; then rmmod cam_cap; sleep 1; fi
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=4 || echo INSMOD_FAIL
i=0
while [ ! -e /dev/video0 ] && [ $i -lt 20 ]; do sleep 0.5; i=$((i+1)); done
ls -l /dev/video0 2>&1

echo "== mode / mirror registers =="
b16() {
	printf '0x%02x 0x%02x' $((($1 >> 8) & 0xff)) $(($1 & 0xff))
}
r16() {
	i2ctransfer -f -y 10 w2@0x10 $(b16 "$1") r2@0x10 2>&1
}
for r in 0x0100 0x0101 0x0112 0x0114 0x0340 0x0342; do
	printf 'reg %s = %s\n' "$r" "$(r16 "$r")"
done

echo "== fps vs integration time (AE off, again=768 dgain=1024) =="
v4l2-ctl -d /dev/video0 -c auto_exposure=1 -c auto_white_balance=0 \
	-c analogue_gain=768 -c digital_gain=1024 >/dev/null 2>&1
for e in 16 272 1100 3658 12288; do
	v4l2-ctl -d /dev/video0 -c exposure_time_absolute=$e >/dev/null 2>&1
	f=$(nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=15 \
		--stream-to=/dev/null 2>&1 | tail -1)
	printf 'exp=%-6s %s\n' "$e" "$f"
	grep -E '^(timing|avg)' /proc/camcap_info | tail -1
done

echo "== CSI2 packets per captured frame =="
p1=$(busybox devmem 0x1a014adc 32)
a1=$(grep -m1 '^arm_count' /proc/camcap_info | tr -dc 0-9)
nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=20 \
	--stream-to=/dev/null >/dev/null 2>&1 &
SP=$!
sleep 4
pm=$(busybox devmem 0x1a014adc 32)
am=$(grep -m1 '^arm_count' /proc/camcap_info | tr -dc 0-9)
wait $SP
p2=$(busybox devmem 0x1a014adc 32)
a2=$(grep -m1 '^arm_count' /proc/camcap_info | tr -dc 0-9)
echo "pkt: $p1 -> $pm -> $p2"
echo "arm: $a1 -> $am -> $a2"
d1=$((pm - p1))
d2=$((p2 - pm))
f1=$((am - a1))
f2=$((a2 - am))
echo "first 4s: dpkt=$d1 frames=$f1 per-frame=$((d1 / (f1 > 0 ? f1 : 1)))"
echo "rest    : dpkt=$d2 frames=$f2 per-frame=$((d2 / (f2 > 0 ? f2 : 1)))"
grep -E '^(timing|avg)' /proc/camcap_info | tail -1

echo "== crash scan =="
dmesg | grep -ciE 'oops|paging request'
echo DONE
