#!/bin/sh
# zz_sw_test.sh - acceptance test for driver-side mode switching.
#
# Covers both userspace entry points: the /proc/camcap "mode <name> [bin]"
# command and VIDIOC_S_FMT / VIDIOC_S_PARM.  For every mode it checks the sensor
# registers actually moved and that the CSI2 packet counter is running, then
# streams frames and reports the measured rate.
set -u
W=/dev/video0
PB=/proc/camcap

pkt() {
	a=$(busybox devmem 0x1a014adc 32 2>/dev/null)
	sleep 1
	b=$(busybox devmem 0x1a014adc 32 2>/dev/null)
	if [ "$a" != "$b" ]; then echo "  [$1] SENDING  $a -> $b"
	else echo "  [$1] SILENT   stuck at $a"; fi
}

sens() {
	echo "  [$1] 0100=$(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1) 0112=$(i2ctransfer -f -y 10 w2@0x10 0x01 0x12 r1 2>&1) 0306=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x06 r1 2>&1) 0307=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x07 r1 2>&1) 0900=$(i2ctransfer -f -y 10 w2@0x10 0x09 0x00 r1 2>&1) 0340=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x40 r1 2>&1) 0341=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x41 r1 2>&1)"
}

modecmd() {
	dmesg -c >/dev/null 2>&1
	echo "mode $1 $2" > $PB; rc=$?
	echo "  [$3] /proc: mode $1 $2 -> rc=$rc"
	dmesg | grep -E 'cam_cap: (mode|rx):' | grep -vE '[0-9]+/[0-9]+ 0x' | tail -5 | sed 's/^/  /'
	sleep 1
	sens "$3"
	pkt "$3"
}

stream() {
	timeout 25 v4l2-ctl -d $W --stream-mmap --stream-count=$1 --stream-to=/dev/null >/dev/null 2>&1
	echo "  [$2] stream $1 frames:"
	grep -E '^(avg|timing|dist|stats)' /proc/camcap_info 2>/dev/null | sed 's/^/    /'
}

echo "=== 0. bring-up preview binned (mode_trace=1) ==="
pkill -x cheese 2>/dev/null
fuser -k $W 2>/dev/null
sleep 0.5
rmmod cam_cap 2>/dev/null
MODE_W=4000 MODE_H=3000 MODE_STRIDE=6000 MODE_FRAME=18874368 \
	sh /root/zz_v80.sh 2>&1 | grep -E 'IMX582 (ALIVE|DEAD)|frame_ready'
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=8 pipeline=1 mode_trace=1" \
	sh /root/zz_cam_up.sh 2>&1 | grep -E '\[!!\]|registered|streaming'
sleep 1
sens "0 preview-bin2"
pkt "0 preview-bin2"
stream 30 "0 preview-bin2"

echo
echo "=== 1. /proc mode custom2 1 (1920x1080, 1370 Mbps) ==="
modecmd custom2 1 "1 custom2"
stream 40 "1 custom2"

echo
echo "=== 2. S_FMT 4000x2256 -> normal_video (same 1370 Mbps as preview) ==="
timeout 20 v4l2-ctl -d $W --set-fmt-video=width=4000,height=2256,pixelformat=YUYV 2>&1 | sed 's/^/  /'
timeout 20 v4l2-ctl -d $W --get-fmt-video 2>&1 | grep -E 'Width|Height|Bytes' | sed 's/^/  /'
sens "2 normal_video"
stream 30 "2 normal_video"

echo
echo "=== 3. S_PARM 60 -> custom3 (4000x2256, 1964 Mbps, retime) ==="
timeout 20 v4l2-ctl -d $W --set-parm=60 2>&1 | sed 's/^/  /'
sleep 1
sens "3 custom3"
pkt "3 custom3"
stream 60 "3 custom3"

echo
echo "=== 4. S_FMT 1920x1080 -> custom2, then S_PARM 240 -> hs_video (1964 Mbps) ==="
timeout 20 v4l2-ctl -d $W --set-fmt-video=width=1920,height=1080,pixelformat=YUYV 2>&1 | sed 's/^/  /'
timeout 20 v4l2-ctl -d $W --set-parm=240 2>&1 | sed 's/^/  /'
sleep 1
sens "4 hs_video"
pkt "4 hs_video"
stream 60 "4 hs_video"

echo
echo "=== 5. back to preview binned through /proc ==="
modecmd preview 2 "5 preview-bin2"
stream 30 "5 preview-bin2"

echo
echo "=== health ==="
echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
free -m | head -2 | sed 's/^/  /'
uptime
echo "### zz_sw_test done"
