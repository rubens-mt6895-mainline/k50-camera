#!/bin/sh
# zz_cal1.sh - exposure / gain response calibration for the AE loop.
#
# Uses the /proc/camcap path on purpose: the V4L2 AE loop only runs inside the
# capture thread, so while nobody streams /dev/video0 the sensor stays exactly
# where this script puts it.
#
# One device task at a time, low priority, no background work.
set -u

renice -n 19 -p $$ >/dev/null 2>&1

b16() {
	# b16 <val16> - two hex bytes on stdout
	printf '0x%02x 0x%02x' $((($1 >> 8) & 0xff)) $(($1 & 0xff))
}

w16() {
	# w16 <reg16> <val16>
	i2ctransfer -f -y 10 w4@0x10 $(b16 "$1") $(b16 "$2")
}

r16() {
	# r16 <reg16> - reads the register back
	i2ctransfer -f -y 10 w2@0x10 $(b16 "$1") r2@0x10 2>&1 | tr '\n' ' '
	echo
}

point() {
	# point <exposure> <analogue gain> <digital gain>
	w16 0x0202 "$1"
	w16 0x0204 "$2"
	w16 0x020e "$3"
	echo "cfg 1 0 4000 0 3000 6000 3000 6000" > /proc/camcap
	echo arm > /proc/camcap
	sleep 0.3
	echo arm > /proc/camcap
	echo stats > /proc/camcap
	printf 'exp=0x%04x again=0x%04x dgain=0x%04x | ' "$1" "$2" "$3"
	grep -E '^(stats|last_result)' /proc/camcap_info | tr '\n' ' '
	echo
}

echo "=== sensor registers before the sweep ==="
printf '0x0202 = '; r16 0x0202
printf '0x0204 = '; r16 0x0204
printf '0x020e = '; r16 0x020e
echo

echo "=== exposure sweep at again=0x0300 dgain=0x0400 ==="
for e in 0x0020 0x0060 0x0100 0x0200 0x0380 0x0500 0x0800 0x0a00 0x0d00 0x0f00; do
	point "$e" 0x0300 0x0400
done

echo
echo "=== analogue gain sweep at exp=0x0d00 dgain=0x0400 ==="
for g in 0x0100 0x0180 0x0200 0x0280 0x0300 0x03c0 0x0700; do
	point 0x0d00 "$g" 0x0400
done

echo
echo "=== digital gain sweep at exp=0x0d00 again=0x0300 ==="
for d in 0x0100 0x0200 0x0400 0x0800 0x1000; do
	point 0x0d00 0x0300 "$d"
done

echo
echo "=== back to the working point ==="
point 0x0380 0x0300 0x0400
