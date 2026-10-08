#!/bin/sh
# zz_expo3.sh - front camera (IMX596) follow-up: are the captured frames live at
# all, and do ANY of the three control registers change the pixels?
#
# While a stream runs with the driver's I2C writes disabled (sensor_ctl=0) we
# write and read back 0x0202 (coarse integration), 0x0204 (analogue gain) and
# 0x020e (digital gain), printing the frame statistics after each.  Then we
# remove the screen light source (kill the white pattern) for a pure
# scene-change control: if the statistics do not move, the frames we read are
# not coming from the front sensor.
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

echo "=== zz_expo3: front camera register + liveness probe ==="
date

pkill -x cheese 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
grep -q '^cam_cap' /proc/modules && rmmod cam_cap 2>/dev/null
dmesg -c >/dev/null 2>&1

WAY="XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0"
setsid env $WAY gst-launch-1.0 -q videotestsrc pattern=white is-live=true \
	! video/x-raw,width=1440,height=3200,framerate=2/1 \
	! videoconvert ! waylandsink fullscreen=true >/tmp/scr.log 2>&1 &
sleep 3
echo "  gst: $(pgrep -x gst-launch-1.0 | tr '\n' ' ')"

$G 158 1 >/dev/null 2>&1
$I w2@0x35 0x0a 0x36 >/dev/null 2>&1
$I w2@0x35 0x06 0xbf >/dev/null 2>&1
$I w2@0x35 0x04 0x89 >/dev/null 2>&1
$I w2@0x35 0x03 0x65 >/dev/null 2>&1
sleep 0.3
echo "GPIO150 func1" >$P 2>/dev/null
$G 153 0 >/dev/null 2>&1
sleep 0.05
$G 153 1 >/dev/null 2>&1
sleep 0.05
$N python3 /root/sensor_bring.py $BUS 0x10 /root/imx596_init.txt \
	/root/imx596_2592x1952.txt 2>&1 | tail -3
$N python3 /root/csirx_bring.py 0 678 3 2>&1 | tail -3

ARGS="v4l2_enable=1 conv_threads=4 pipeline=1"
ARGS="$ARGS ae_enable=0 awb_enable=0 af_enable=0 vcm_enable=0 sensor_ctl=0"
ARGS="$ARGS route_intf=0 dphy_base=0x11c82000 route_mux=1 cammux=3"
ARGS="$ARGS exp_hsize=$W exp_vsize=$H out_width=$OW out_height=$OH v4l2_bin=$BIN"
ARGS="$ARGS i2c_bus=$BUS i2c_addr=0x10 exp_max=8000"
insmod $KO $ARGS || { echo "insmod failed"; exit 1; }
echo route >/proc/camcap 2>/dev/null
sleep 0.3

st() { grep -E '^stats' /proc/camcap_info; }

probe() {
	# probe <name> <reg> <value>
	R=$2
	V=$3
	HI=$(printf '%02x' $(( (V >> 8) & 0xff )))
	LO=$(printf '%02x' $(( V & 0xff )))
	$IB w4@0x10 $R $HI $LO >/dev/null 2>&1 || echo "    write $R=$V FAILED"
	sleep 1.0
	RB=$($IB w2@0x10 $R r2@0x10 2>&1)
	echo "  [$1 reg=$R val=$V readback=$RB] $(st)"
}

$N timeout 120 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=900 \
	--stream-to=/dev/null >/tmp/stream.log 2>&1 &
SPID=$!
sleep 3

echo "--- baseline"
echo "  [baseline] $(st)"
probe "coarse" 0x02 0x1000
probe "coarse" 0x02 0x0010
probe "again " 0x04 0x03f0
probe "again " 0x04 0x0100
probe "dgain " 0x0e 0x1000
probe "dgain " 0x0e 0x0400

echo "--- scene-change control: remove the white pattern"
pkill -x gst-launch-1.0 2>/dev/null
sleep 2.5
echo "  [screen off] $(st)"
sleep 2.5
echo "  [screen off again] $(st)"

kill $SPID 2>/dev/null
wait $SPID 2>/dev/null
rmmod cam_cap 2>/dev/null
sleep 0.5
sh /root/zz_cam_up.sh >/tmp/restore.log 2>&1
tail -4 /tmp/restore.log
echo "crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog|Unable to handle')"
echo "=== done ==="
