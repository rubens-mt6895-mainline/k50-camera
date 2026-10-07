#!/bin/sh
# zz_sw_probe4.sh - the S_FMT path switches (probe 3 showed /proc "mode" fails
# with EIO), so use it and ask the link counter whether the sensor transmits:
#
#   A  full bring-up (preview), packet counter baseline
#   B  VIDIOC_S_FMT 1920x1080 (custom2) through v4l2-ctl, sensor registers read
#      back, packet counter -> is the sensor in custom2 and sending?
#   C  a short stream: do frames reach the application?
#   D  recovery
#
# If B says SENDING and C still says NO FRAMES, the sensor is fine and the
# problem is on the receive side (CAMSV / SENINF geometry for the new mode).
set -u
P=/sys/module/cam_cap/parameters
W=/dev/video0
PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=4 pipeline=1"

pkt() {
	a=$(busybox devmem 0x1a014adc 32 2>/dev/null)
	sleep 1
	b=$(busybox devmem 0x1a014adc 32 2>/dev/null)
	if [ "$a" != "$b" ]; then
		echo "  [$1] SENDING  pkt $a -> $b"
	else
		echo "  [$1] SILENT   pkt stuck at $a"
	fi
}

sens() {
	echo "  [$1] 0306=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x06 r1 2>&1) 0307=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x07 r1 2>&1) 0340=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x40 r1 2>&1) 0341=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x41 r1 2>&1)"
}

ae() {
	grep '^ae ' /proc/camcap_info 2>/dev/null | sed 's/^/  /'
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

echo "=== A. full bring-up (preview) ==="
bringup
pkt "A preview"
sens "A"
ae "A"

echo
echo "=== B. S_FMT 1920x1080 (custom2) through the application path ==="
dmesg -c >/dev/null
timeout 10 v4l2-ctl -d $W --set-fmt-video=width=1920,height=1080,pixelformat=YUYV 2>&1 | sed 's/^/  /'
echo "  rc=$?"
sleep 1
timeout 10 v4l2-ctl -d $W --get-fmt-video 2>&1 | sed 's/^/  /'
dmesg | grep -E 'cam_cap: (mode:|rx:|v4l2: s_fmt)' | sed 's/^/  /'
sleep 1
sens "B"
pkt "B after S_FMT"
ae "B"

echo
echo "=== C. short stream after the switch ==="
timeout 20 v4l2-ctl -d $W --stream-mmap --stream-count=20 --stream-to=/dev/null 2>&1 | sed 's/^/  /'
echo "  rc=$?"
sleep 1
grep -E '^(avg|stats|timing|dist) ' /proc/camcap_info 2>/dev/null | sed 's/^/  /'
ae "C"

echo
echo "=== D. recovery ==="
bringup
pkt "D recovered"
echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
uptime
echo "### zz_sw_probe4 done"
