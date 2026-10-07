#!/bin/sh
# zz_sw_probe5.sh - why does the driver's table replay leave the sensor dead?
#
# probe 4: after VIDIOC_S_FMT to custom2 the driver logged a successful switch,
# but the sensor read back all zeroes (0306/0307/0340/0341 = 0) and the CSI2
# packet counter stopped.  The userspace path (scripts/zz_v80.sh) differs in two
# ways: it pulses the sensor reset (GPIO155) before replaying, and it writes
# each register as its own ~1 ms i2ctransfer instead of a tight kernel loop.
# This separates those two, using the packet counter as the link oracle:
#
#   A  full bring-up (preview)                                    baseline
#   B  module unloaded, replay custom2 with NO reset               reset needed?
#   C  module loaded with mode_init_replay=0, S_FMT switch         INIT replay?
#   D  module loaded normally, S_FMT switch                        control
#
# Every step ends by reading back 0x0306/0x0307/0x0340/0x0341 (custom2 is
# 0x0307=0x99, VTS 2100 = 0x0834) and sampling the packet counter.
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
	echo "  [$1] 0306=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x06 r1 2>&1) 0307=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x07 r1 2>&1) 0340=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x40 r1 2>&1) 0341=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x41 r1 2>&1)"
}
# custom2 expects 0307=0x99 and VTS 2100 (0340/0341 = 0x0834); preview is 0xb4 / 0x0ce4

resetpulse() {	# step 5 of zz_v80.sh
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
		sh /root/zz_v80.sh 2>&1 | grep -E 'IMX582 (ALIVE|DEAD)'
	CAM_CAP_PARAMS="$PARAMS" sh /root/zz_cam_up.sh >/dev/null 2>&1
	sleep 1
}

sfmt() {	# sfmt <w> <h> - the application path
	dmesg -c >/dev/null
	timeout 10 v4l2-ctl -d $W --set-fmt-video=width=$1,height=$2,pixelformat=YUYV >/dev/null 2>&1
	echo "  s_fmt rc=$?"
	sleep 1
	dmesg | grep -E 'cam_cap: (mode:|rx:|v4l2: s_fmt)' | sed 's/^/  /'
}

echo "=== A. full bring-up (preview) ==="
bringup
sens "A preview"
pkt "A preview"

echo
echo "=== B. module unloaded, replay custom2 with NO reset ==="
fuser -k $W 2>/dev/null
sleep 0.5
rmmod cam_cap 2>&1 | sed 's/^/  /'
sleep 0.5
lsmod | grep -c cam_cap | sed 's/^/  cam_cap loaded: /'
IMX582_MODE=custom2 nice -n 19 python3 /root/imx582_bring.py 2>&1 | tail -1 | sed 's/^/  /'
sleep 1
sens "B no reset"
pkt "B no reset"

echo
echo "=== C. fresh bring-up, then driver switch with mode_init_replay=0 ==="
bringup
echo 0 > $P/mode_init_replay
echo "  mode_init_replay=$(cat $P/mode_init_replay)"
sens "C before"
echo "  --- /proc path ---"
echo "mode custom2 1" > /proc/camcap 2>&1 || echo "  /proc mode rc=$?"
sleep 1
sens "C after /proc"
echo "  --- application path ---"
sfmt 1920 1080
sens "C after s_fmt"
pkt "C after s_fmt"

echo
echo "=== D. fresh bring-up, driver switch with the INIT replay (control) ==="
bringup
echo "  mode_init_replay=$(cat $P/mode_init_replay)"
sfmt 1920 1080
sens "D after s_fmt"
pkt "D after s_fmt"

echo
echo "=== E. recovery + health ==="
bringup
sens "E recovered"
pkt "E recovered"
echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
uptime
echo "### zz_sw_probe5 done"
