#!/bin/sh
# zz_expo4.sh - front camera (IMX596) control-register response, done right.
#
# zz_expo3.sh failed to write at all (the helper passed 1 register byte to w4),
# so re-run with a correct 2-byte register.  The mode table we replay leaves
# 0x0202/0x0203 = 0x1800 (6144 lines) and 0x0204/0x0205 = 0x0000, so the
# interesting sweeps are exposure 0x0010 .. 0x1800, analogue gain up to
# 0x03f0 and digital gain 0x020e = 0x1000 (16x).  Last probe switches the
# sensor's own streaming bit off and on (0x0100) -- that can only bite if the
# frames really come from this sensor and it honours its control registers.
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

echo "=== zz_expo4: front camera control-register response ==="
date

pkill -x cheese 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
grep -q '^cam_cap' /proc/modules && rmmod cam_cap 2>/dev/null
dmesg -c >/dev/null 2>&1

WAY="XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0"
setsid env $WAY gst-launch-1.0 -q videotestsrc pattern=white is-live=true \
	! video/x-raw,width=1440,height=3200,framerate=2/1 \
	! videoconvert ! waylandsink >/tmp/scr.log 2>&1 &
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
	/root/imx596_2592x1952.txt 2>&1 | tail -2
$N python3 /root/csirx_bring.py 0 678 3 2>&1 | grep -E 'PKT|FINAL' | tail -2

ARGS="v4l2_enable=1 conv_threads=4 pipeline=1"
ARGS="$ARGS ae_enable=0 awb_enable=0 af_enable=0 vcm_enable=0 sensor_ctl=0"
ARGS="$ARGS route_intf=0 dphy_base=0x11c82000 route_mux=1 cammux=3"
ARGS="$ARGS exp_hsize=$W exp_vsize=$H out_width=$OW out_height=$OH v4l2_bin=$BIN"
ARGS="$ARGS i2c_bus=$BUS i2c_addr=0x10 exp_max=8000 arm_trace=1"
insmod $KO $ARGS || { echo "insmod failed"; exit 1; }
echo route >/proc/camcap 2>/dev/null
sleep 0.3

st() {
	grep -E '^stats' /proc/camcap_info
	awk '/^dist/{print "  dist",$0}' /proc/camcap_info
}

# probe <label> <reg_hi> <reg_lo> <value>
probe() {
	L=$1; R1=$2; R2=$3; V=$4
	HI=$(printf '%02x' $(( (V >> 8) & 0xff )))
	LO=$(printf '%02x' $(( V & 0xff )))
	if $IB w4@0x10 $R1 $R2 $HI $LO >/dev/null 2>&1; then
		W="ok"
	else
		W="FAILED"
	fi
	sleep 1.2
	RB=$($IB w2@0x10 $R1 $R2 r2@0x10 2>&1 | tr '\n' ' ')
	echo "  [$L $R1$R2=$V write=$W readback=$RB] $(st)"
}

$N timeout 150 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1200 \
	--stream-to=/dev/null >/tmp/stream.log 2>&1 &
SPID=$!
sleep 3

echo "--- baseline (table default 0x0202=0x1800)"
echo "  [baseline] $(st)"
probe "coarse" 0x02 0x02 0x0010
probe "coarse" 0x02 0x02 0x1800
probe "coarse" 0x02 0x02 0x1000
probe "again " 0x02 0x04 0x03f0
probe "again " 0x02 0x04 0x0000
probe "dgain " 0x02 0x0e 0x1000
probe "dgain " 0x02 0x0e 0x0100
echo "--- streaming bit off (only meaningful if these frames are live)"
probe "stream" 0x01 0x00 0x0000
sleep 2
probe "stream" 0x01 0x00 0x0001
sleep 1
echo "  [after stream on] $(st)"

kill $SPID 2>/dev/null
wait $SPID 2>/dev/null
rmmod cam_cap 2>/dev/null
sleep 0.5
sh /root/zz_cam_up.sh >/tmp/restore.log 2>&1
tail -3 /tmp/restore.log
echo "crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog|Unable to handle')"
echo "=== done ==="
