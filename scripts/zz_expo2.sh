#!/bin/sh
# zz_expo2.sh - front camera (IMX596): does an exposure change reach the sensor?
#
# Two independent probes, because the earlier A/B could not tell them apart:
#   1. the driver writes exp_def itself (sensor_ctl=1) -- capture its own
#      "exposure write ... failed" warnings from dmesg;
#   2. the driver is told to keep its hands off I2C (sensor_ctl=0) and we write
#      0x0202 from user space with i2ctransfer *while* the stream runs, so a
#      working wire and a working sensor must show a brighter frame.
# The bring-up block is copied from out/re/zz_ab_scr.sh.
set -u
N="nice -n 19"
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
I="i2ctransfer -f -y 11"
IB="i2ctransfer -f -y 8"
BUS=8
W=2592
H=1952
BIN=2
OW=$((W / BIN))
OH=$((H / BIN))
KO=/root/cam_cap.ko

echo "=== zz_expo2: front camera exposure response ==="
date
uptime

echo "--- 0. free the camera"
pkill -x cheese 2>/dev/null
pkill -x gst-launch-1.0 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
if grep -q '^cam_cap' /proc/modules; then
	rmmod cam_cap 2>&1 || { echo "ABORT: cam_cap busy"; exit 1; }
fi
dmesg -c >/dev/null 2>&1

echo "--- 1. screen pattern (light source for the front camera)"
WAY="XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0"
setsid env $WAY gst-launch-1.0 -q videotestsrc pattern=white is-live=true \
	! video/x-raw,width=1440,height=3200,framerate=2/1 \
	! videoconvert ! waylandsink fullscreen=true >/tmp/scr.log 2>&1 &
sleep 3
echo "  gst: $(pgrep -x gst-launch-1.0 | tr '\n' ' ')"

echo "--- 2. front camera power-up"
$G 158 1 >/dev/null 2>&1
$I w2@0x35 0x0a 0x36 >/dev/null 2>&1
$I w2@0x35 0x06 0xbf >/dev/null 2>&1
$I w2@0x35 0x04 0x89 >/dev/null 2>&1
$I w2@0x35 0x03 0x65 >/dev/null 2>&1
sleep 0.3
echo "  fan 0x03=$($I w1@0x35 0x03 r1 2>&1)"
echo "GPIO150 func1" >$P 2>/dev/null
$G 153 0 >/dev/null 2>&1
sleep 0.05
$G 153 1 >/dev/null 2>&1
sleep 0.05
$N python3 /root/sensor_bring.py $BUS 0x10 /root/imx596_init.txt \
	/root/imx596_2592x1952.txt 2>&1 | tail -5
$N python3 /root/csirx_bring.py 0 678 3 2>&1 | tail -6

load() {
	ARGS="v4l2_enable=1 conv_threads=4 pipeline=1"
	ARGS="$ARGS ae_enable=0 awb_enable=0 af_enable=0 vcm_enable=0"
	ARGS="$ARGS route_intf=0 dphy_base=0x11c82000 route_mux=1 cammux=3"
	ARGS="$ARGS exp_hsize=$W exp_vsize=$H out_width=$OW out_height=$OH v4l2_bin=$BIN"
	ARGS="$ARGS i2c_bus=$BUS i2c_addr=0x10 exp_max=8000 sensor_ctl=$1 exp_def=$2"
	insmod $KO $ARGS 2>/tmp/ins.log || { echo "  insmod FAILED: $(tail -2 /tmp/ins.log | tr '\n' ' ')"; return 1; }
	echo route >/proc/camcap 2>/dev/null
	sleep 0.3
}

echo "--- 3. probe A: the driver's own writes (sensor_ctl=1)"
for E in 16 512; do
	dmesg -c >/dev/null 2>&1
	load 1 $E || continue
	$N timeout 25 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=10 \
		--stream-to=/dev/null >/dev/null 2>&1
	echo "  [driver exp_def=$E] $(grep -E '^(stats|ae)' /proc/camcap_info | tr '\n' '|')"
	echo "  [driver exp_def=$E] i2c warnings: $(dmesg | grep -c 'cam_cap: .*write .*failed')"
	dmesg | grep 'cam_cap: .*write .*failed' | head -3 | sed 's/^/    /'
	rmmod cam_cap 2>/dev/null
	sleep 0.3
done

echo "--- 4. probe B: user-space 0x0202 writes while streaming (sensor_ctl=0)"
load 0 16 || exit 1
$N timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=300 \
	--stream-to=/dev/null >/tmp/stream.log 2>&1 &
SPID=$!
sleep 2
for V in 0x0010 0x0040 0x0100 0x0400 0x1000 0x0040; do
	HI=$(printf '%02x' $(( (V >> 8) & 0xff )))
	LO=$(printf '%02x' $(( V & 0xff )))
	$IB w4@0x10 0x02 0x02 $HI $LO >/dev/null 2>&1 \
		|| echo "    write $V FAILED"
	sleep 1.2
	echo "  [user 0x0202=$V] $(grep -E '^stats' /proc/camcap_info)"
done
kill $SPID 2>/dev/null
wait $SPID 2>/dev/null
echo "  stream log: $(tail -1 /tmp/stream.log)"
rmmod cam_cap 2>/dev/null

echo "--- 5. cleanup + restore the main camera"
pkill -x gst-launch-1.0 2>/dev/null
sleep 0.5
sh /root/zz_cam_up.sh >/tmp/restore.log 2>&1
tail -6 /tmp/restore.log
echo "--- 6. health"
echo "crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog|Unable to handle')"
uptime
echo "=== done ==="
