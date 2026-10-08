#!/bin/sh
# zz_ab_scr.sh - on-device A/B of the focus metric (old linear luma vs new
# per-mille) on the FRONT IMX596, lit by the phone's own screen.
#
# Why the front camera: the metric is accumulated in every converter path
# (src/cam_cap.c 2x2 / full-ref / full-fast) and is NOT gated by af_enable or
# vcm_enable, so /proc/camcap_info reports it for any sensor.  The main camera
# sits in a dark room (post-black level ~8 at full AE) and can never reach the
# old metric's clipping threshold, but the front camera stares straight into the
# panel and can.
set -u
N="nice -n 19"
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
I="i2ctransfer -f -y 11"
BUS=8
W=2592
H=1952
BIN=2
OW=$((W / BIN))
OH=$((H / BIN))
KO_NEW=/root/cam_cap.ko
KO_OLD=/root/cam_cap.ko.old

echo "=== zz_ab_scr: focus-metric A/B (front IMX596 lit by the panel) ==="
date
uptime

echo "--- prereqs"
for f in /root/sensor_bring.py /root/csirx_bring.py /root/imx596_init.txt \
	/root/imx596_2592x1952.txt "$KO_OLD" "$KO_NEW"; do
	[ -e "$f" ] && echo "  ok   $f" || echo "  MISS $f"
done
[ -e /root/imx596_init.txt ] || { echo "ABORT: front tables missing"; exit 1; }
[ -e "$KO_OLD" ] || { echo "ABORT: $KO_OLD missing"; exit 1; }
md5sum "$KO_OLD" "$KO_NEW"

echo "--- 0. free the camera"
pkill -x cheese 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
if grep -q '^cam_cap' /proc/modules; then
	rmmod cam_cap 2>&1 || { echo "ABORT: cam_cap busy"; exit 1; }
fi
dmesg -c >/dev/null 2>&1

echo "--- 1. screen pattern (bright, low contrast = light source)"
pkill -x gst-launch-1.0 2>/dev/null
sleep 0.5
WAY="XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0"
setsid env $WAY gst-launch-1.0 -q videotestsrc pattern=checkers-8 is-live=true \
	! video/x-raw,width=1440,height=3200,framerate=2/1 \
	! videobalance contrast=0.25 brightness=0.35 \
	! videoconvert ! waylandsink fullscreen=true >/tmp/scr.log 2>&1 &
sleep 3
if ! pgrep -x gst-launch-1.0 >/dev/null 2>&1; then
	echo "  videobalance pipeline died, retry without it"
	tail -3 /tmp/scr.log 2>/dev/null
	setsid env $WAY gst-launch-1.0 -q videotestsrc pattern=checkers-8 is-live=true \
		! video/x-raw,width=1440,height=3200,framerate=2/1 \
		! videoconvert ! waylandsink fullscreen=true >>/tmp/scr.log 2>&1 &
	sleep 3
fi
echo "  gst: $(pgrep -x gst-launch-1.0 | tr '\n' ' ')"
tail -3 /tmp/scr.log 2>/dev/null

echo "--- 2. front camera power-up"
$G 158 1 >/dev/null 2>&1
$I w2@0x35 0x0a 0x36 2>&1
$I w2@0x35 0x06 0xbf 2>&1
$I w2@0x35 0x04 0x89 2>&1
$I w2@0x35 0x03 0x65 2>&1
sleep 0.3
echo "  fan 0x03=$($I w1@0x35 0x03 r1 2>&1)"
echo "GPIO150 func1" >$P 2>/dev/null
$G 153 0 >/dev/null 2>&1
sleep 0.05
$G 153 1 >/dev/null 2>&1
sleep 0.05
$N python3 /root/sensor_bring.py $BUS 0x10 /root/imx596_init.txt \
	/root/imx596_2592x1952.txt 2>&1 | tail -5
$N python3 /root/csirx_bring.py 0 678 3 2>&1 | tail -8

echo "--- 3. exposure sweep x module (bin $BIN -> ${OW}x${OH})"
for E in 8 16 32 64 128 256 512; do
	for M in "$KO_OLD old" "$KO_NEW new"; do
		set -- $M
		KO=$1
		TAG=$2
		ARGS="v4l2_enable=1 conv_threads=4 pipeline=1"
		ARGS="$ARGS ae_enable=0 awb_enable=0 af_enable=0 vcm_enable=0"
		ARGS="$ARGS route_intf=0 dphy_base=0x11c82000 route_mux=1 cammux=3"
		ARGS="$ARGS exp_hsize=$W exp_vsize=$H out_width=$OW out_height=$OH v4l2_bin=$BIN"
		ARGS="$ARGS i2c_bus=$BUS i2c_addr=0x10 exp_def=$E exp_max=8000"
		if ! insmod "$KO" $ARGS 2>/tmp/ins.log; then
			echo "  [$TAG exp=$E] insmod FAILED: $(tail -2 /tmp/ins.log | tr '\n' ' ')"
			continue
		fi
		echo route >/proc/camcap 2>/dev/null
		sleep 0.3
		if [ "$TAG" = "new" ] && [ "$E" = "64" ]; then
			$N timeout 25 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=8 \
				--stream-to=/root/ab_new_64.yuyv >/dev/null 2>&1
		elif [ "$TAG" = "old" ] && [ "$E" = "64" ]; then
			$N timeout 25 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=8 \
				--stream-to=/root/ab_old_64.yuyv >/dev/null 2>&1
		else
			$N timeout 25 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=10 \
				--stream-to=/dev/null >/dev/null 2>&1
		fi
		echo "  [$TAG exp=$E] $(grep -E '^(stats|af|ae|avg)' /proc/camcap_info 2>/dev/null | tr '\n' '|')"
		rmmod cam_cap 2>/dev/null || echo "  [$TAG exp=$E] rmmod FAILED"
		sleep 0.3
	done
done

echo "--- 4. cleanup + restore the main camera"
pkill -x gst-launch-1.0 2>/dev/null
if grep -q '^cam_cap' /proc/modules; then
	rmmod cam_cap 2>/dev/null
fi
sleep 0.5
sh /root/zz_cam_up.sh >/tmp/restore.log 2>&1
tail -8 /tmp/restore.log
$N timeout 25 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=8 \
	--stream-to=/dev/null 2>&1 | tail -2
grep -E '^(source|output|avg|stats|af|timing)' /proc/camcap_info 2>/dev/null | head -8

echo "--- 5. health"
echo "crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog|Unable to handle')"
free | head -2
uptime
echo "=== done ==="
