#!/bin/sh
# zz_sw_probe6.sh - recover the sensor, then isolate the reset pulse.
#
# probe 5 left the sensor dead: after the driver's S_FMT switch the mode
# registers read 0x00 and no packets flow, and a following full bring-up did
# not restore it (0307=0x68, VTS 0x185c - a state no table asks for).  The
# userspace bring-up itself always pulses the sensor reset first, so this run
# recovers first and then replays the custom2 tables with the module loaded,
# with and without that reset pulse, using the CSI2 packet counter as the
# oracle:
#
#   0  recovery: rmmod, reset, full bring-up -> preview streaming again?
#   1  module loaded, userspace replay of custom2, NO reset
#   2  module loaded, reset + userspace replay of custom2
#   3  recovery again
set -u
P=/sys/module/cam_cap/parameters
W=/dev/video0
PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=4 pipeline=1"

pkt() {
	a=$(busybox devmem 0x1a014adc 32 2>/dev/null)
	sleep 1
	b=$(busybox devmem 0x1a014adc 32 2>/dev/null)
	if [ "$a" != "$b" ]; then echo "  [$1] SENDING  pkt $a -> $b"
	else echo "  [$1] SILENT   pkt stuck at $a"; fi
}

sens() {
	echo "  [$1] 0300=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x00 r1 2>&1) 0306=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x06 r1 2>&1) 0307=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x07 r1 2>&1) 0340=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x40 r1 2>&1) 0341=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x41 r1 2>&1)"
	echo "        0100=$(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1) id=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x05 r1 2>&1)/$(i2ctransfer -f -y 10 w2@0x10 0x00 0x06 r1 2>&1)"
}

resetpulse() {
	/root/gpiotoolG 155 0 >/dev/null 2>&1
	sleep 0.05
	/root/gpiotoolG 155 1 >/dev/null 2>&1
	sleep 0.1
}

bringup() {
	pgrep -x cheese >/dev/null 2>&1 && { pkill -x cheese; sleep 1; }
	fuser -k $W 2>/dev/null
	sleep 0.5
	rmmod cam_cap 2>/dev/null
	MODE_W=4000 MODE_H=3000 MODE_STRIDE=6000 MODE_FRAME=18874368 \
		sh /root/zz_v80.sh 2>&1 | grep -E 'IMX582 (ALIVE|DEAD)|frame_ready'
	CAM_CAP_PARAMS="$PARAMS" sh /root/zz_cam_up.sh >/dev/null 2>&1
	sleep 1
}

echo "=== 0. recovery ==="
bringup
sens "0 preview"
pkt "0 preview"

echo
echo "=== 1. module loaded, userspace replay custom2, NO reset ==="
IMX582_MODE=custom2 nice -n 19 python3 /root/imx582_bring.py 2>&1 | tail -1 | sed 's/^/  /'
sleep 1
sens "1 no reset"
pkt "1 no reset"

echo
echo "=== 2. module loaded, reset + userspace replay custom2 ==="
resetpulse
IMX582_MODE=custom2 nice -n 19 python3 /root/imx582_bring.py 2>&1 | tail -1 | sed 's/^/  /'
sleep 1
sens "2 with reset"
pkt "2 with reset"

echo
echo "=== 3. recovery again ==="
bringup
sens "3 preview"
pkt "3 preview"

echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
echo "  i2c errors: $(dmesg | grep -icE 'i2c|ack error|timeout')"
uptime
echo "### zz_sw_probe6 done"
