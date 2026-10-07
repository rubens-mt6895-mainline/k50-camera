#!/bin/sh
# zz_cal2.sh - fine sweeps to find the real ceilings of the three gain stages.
set -u

renice -n 19 -p $$ >/dev/null 2>&1

b16() {
	printf '0x%02x 0x%02x' $((($1 >> 8) & 0xff)) $(($1 & 0xff))
}

w16() {
	i2ctransfer -f -y 10 w4@0x10 $(b16 "$1") $(b16 "$2")
}

r16() {
	i2ctransfer -f -y 10 w2@0x10 $(b16 "$1") r2@0x10 2>&1
}

point() {
	w16 0x0202 "$1"
	w16 0x0204 "$2"
	w16 0x020e "$3"
	echo "cfg 1 0 4000 0 3000 6000 3000 6000" > /proc/camcap
	echo arm > /proc/camcap
	sleep 0.3
	echo arm > /proc/camcap
	echo stats > /proc/camcap
	printf 'exp=0x%04x again=0x%04x dgain=0x%04x rb=(' "$1" "$2" "$3"
	printf '%s/%s/%s)' "$(r16 0x0202)" "$(r16 0x0204)" "$(r16 0x020e)"
	printf ' | '
	grep -E '^stats' /proc/camcap_info
}

echo "=== how far does the integration time go? (again=0x0300 dgain=0x0400) ==="
for e in 0x0f00 0x1400 0x2000 0x3000 0x4000 0x6000; do
	point "$e" 0x0300 0x0400
done

echo
echo "=== fine analogue gain map at exp=0x0380 dgain=0x0400 ==="
for g in 0x0300 0x0310 0x0320 0x0340 0x0360 0x0380 0x03a0 0x03c0 0x03f0 0x07ff; do
	point 0x0380 "$g" 0x0400
done

echo
echo "=== how far does the digital gain go? (exp=0x0380 again=0x0300) ==="
for d in 0x1000 0x2000 0x4000 0x7fff; do
	point 0x0380 0x0300 "$d"
done

echo
echo "=== back to the working point ==="
point 0x0380 0x0300 0x0400
