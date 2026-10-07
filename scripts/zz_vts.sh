#!/bin/sh
# zz_vts.sh - sweep VTS live to find how much frame-rate headroom the sensor has.
#
# /proc/camcap_info reports period=33064us at VTS 0x0e4a (3658 lines) => 30.2 fps,
# but the burst ceiling is 33.8 ms and occasional frames stretch to two periods, so
# the average dips under 30 on a busy machine.  VTS is the lever: each line is
# ~9.04 us.  Sensor writes are one 4-byte transfer (reg hi/lo + data hi/lo) - a
# 2-byte data write silently no-ops, which is why the first attempt failed.
set -u
P=/sys/module/cam_cap/parameters

pkill -x cheese 2>/dev/null
sleep 0.5
fuser -k /dev/video0 2>/dev/null
sleep 0.5

rd() {
	echo "  VTS   $(i2ctransfer -y -f 10 w2@0x10 0x03 0x40 r2@0x10 2>&1)"
	echo "  EXP   $(i2ctransfer -y -f 10 w2@0x10 0x02 0x02 r2@0x10 2>&1)"
	echo "  AGAIN $(i2ctransfer -y -f 10 w2@0x10 0x02 0x04 r2@0x10 2>&1)"
	echo "  DGAIN $(i2ctransfer -y -f 10 w2@0x10 0x02 0x0e r2@0x10 2>&1)"
}

wr_reg() {  # $1 = register, $2 = value; one 4 byte transfer
	rhi=$(( ($1 >> 8) & 0xff )); rlo=$(( $1 & 0xff ))
	vhi=$(( ($2 >> 8) & 0xff )); vlo=$(( $2 & 0xff ))
	printf '  write reg %#x = %#x (0x%02x%02x)\n' "$1" "$2" "$vhi" "$vlo"
	i2ctransfer -y -f 10 w4@0x10 $(printf 0x%02x $rhi) $(printf 0x%02x $rlo) \
		$(printf 0x%02x $vhi) $(printf 0x%02x $vlo) 2>&1
}

step() {  # $1 = vts
	echo
	echo "=================== VTS $1 ==================="
	wr_reg 0x0340 "$1"
	echo "$1" > "$P/exp_max"
	sleep 1
	rd
	echo "  exp_max = $(cat $P/exp_max)"
	echo "  --- burst 16 (bare arm ceiling) ---"
	echo "burst 16" > /proc/camcap
	dmesg | grep 'burst:' | tail -1
	echo "  --- 40 frame stream ---"
	nice -n 10 timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=40 \
		--stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1
	grep -E '^avg|^stats' /proc/camcap_info | head -2
}

echo "=== module state ==="
echo "conv_threads=$(cat $P/conv_threads) rb_swap=$(cat $P/rb_swap) exp_max=$(cat $P/exp_max)"
echo
echo "=== baseline (VTS as set by the bring-up) ==="
rd
echo "  --- baseline burst 16 ---"
echo "burst 16" > /proc/camcap
dmesg | grep 'burst:' | tail -1
echo "  --- baseline 40 frame stream ---"
nice -n 10 timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=40 \
	--stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1
grep -E '^avg|^stats' /proc/camcap_info | head -2

step 3570
step 3500
step 3400

echo
echo "=== crash scan (should be 0) ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace' || true
echo "=== loadavg ==="
cat /proc/loadavg
