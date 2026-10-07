#!/bin/sh
# zz_sw_probe3.sh - is the missing piece a hardware reset before the tables?
#
# Probe 2 showed that even a userspace replay of the custom2 tables (HTS 2912 /
# VTS 2100 read back correctly) yields no frames, while the full bring-up does.
# The bring-up differs in exactly one step: it pulses the sensor reset (GPIO155)
# before writing the power-on table, and neither the driver nor
# scripts/imx582_bring.py does.  This measures the link itself, with the CSI2
# packet counter at 0x1a014adc, so it does not depend on the driver's CAMSV
# geometry matching the mode:
#
#   A  full bring-up (reset + receiver + preview tables + module)   -> sensor sends
#   B  driver-side switch to custom2, no reset                      -> sends?
#   C  reset + userspace replay of custom2, module untouched        -> sends?
#   D  full bring-up again (known good)
#   E  reset, then the driver switches to custom3 (1964 Mbps)        -> sends?
#
# No userspace streamer runs, so the queue is never busy and the module can
# always be unloaded (a streamer with no frames loops in DQBUF and then only a
# reboot clears it).
set -u
G=/root/gpiotoolG
P=/sys/module/cam_cap/parameters
W=/dev/video0
PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=4 pipeline=1"

pkt() {	# pkt <label> - is the sensor putting packets on the CSI2 link?
	a=$(busybox devmem 0x1a014adc 32 2>/dev/null)
	ia=$(busybox devmem 0x1a014ac8 32 2>/dev/null)
	sleep 1
	b=$(busybox devmem 0x1a014adc 32 2>/dev/null)
	ib=$(busybox devmem 0x1a014ac8 32 2>/dev/null)
	if [ "$a" != "$b" ]; then
		echo "  [$1] SENDING  pkt $a -> $b   irq $ia -> $ib"
	else
		echo "  [$1] SILENT   pkt stuck at $a   irq $ia -> $ib"
	fi
}

sens() {	# sens <label> - what mode does the sensor itself think it is in?
	echo "  [$1] 0100=$(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1) 0112=$(i2ctransfer -f -y 10 w2@0x10 0x01 0x12 r1 2>&1) 0114=$(i2ctransfer -f -y 10 w2@0x10 0x01 0x14 r1 2>&1)"
	echo "        0306=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x06 r1 2>&1) 0307=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x07 r1 2>&1) 0340=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x40 r1 2>&1) 0341=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x41 r1 2>&1)"
}

resetpulse() {	# the exact step 5 of zz_v80.sh
	$G 155 0 >/dev/null 2>&1
	sleep 0.05
	$G 155 1 >/dev/null 2>&1
	sleep 0.1
}

bringup() {
	free_cam
	rmmod cam_cap 2>/dev/null
	MODE_W=4000 MODE_H=3000 MODE_STRIDE=6000 MODE_FRAME=18874368 \
		sh /root/zz_v80.sh 2>&1 | grep -E 'IMX582 (ALIVE|DEAD)|frame_ready|last_result|zz_v80 done'
	CAM_CAP_PARAMS="$PARAMS" sh /root/zz_cam_up.sh 2>&1 | grep -E 'mode: |\[!!\]'
	sleep 1
}

free_cam() {
	pgrep -x cheese >/dev/null 2>&1 && { pkill -x cheese; sleep 1; }
	fuser -k $W 2>/dev/null
	sleep 0.5
}

echo "=== A. full bring-up (preview) ==="
bringup
pkt "A after full bring-up"
sens "A"

echo
echo "=== B. driver-side switch to custom2, no reset ==="
dmesg -c >/dev/null
echo "mode custom2 1" > /proc/camcap || echo "  [!!] mode command failed"
sleep 1
dmesg | grep -E 'cam_cap: (mode:|rx:)' | tail -2 | sed 's/^/  /'
sens "B"
pkt "B after driver switch (no reset)"

echo
echo "=== C. reset pulse + userspace replay of custom2, module untouched ==="
resetpulse
IMX582_MODE=custom2 nice -n 19 python3 /root/imx582_bring.py 2>&1 | tail -2 | sed 's/^/  /'
sleep 1
sens "C"
pkt "C after reset + userspace replay"

echo
echo "=== D. full bring-up again (known good) ==="
bringup
pkt "D recovered"

echo
echo "=== E. reset, then the driver switches to custom3 (1964 Mbps/lane) ==="
dmesg -c >/dev/null
resetpulse
sleep 0.3
echo "mode custom3 1" > /proc/camcap || echo "  [!!] mode command failed"
sleep 1
dmesg | grep -E 'cam_cap: (mode:|rx:)' | tail -3 | sed 's/^/  /'
sens "E"
pkt "E after reset + driver switch to custom3"

echo
echo "=== F. recovery + health ==="
bringup
pkt "F recovered"
echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
fuser -v $W 2>&1 | sed 's/^/  /'
uptime
echo "### zz_sw_probe3 done"
