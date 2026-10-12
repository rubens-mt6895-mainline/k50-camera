#!/bin/sh
# Bring up ALL FOUR cameras at once and stream each of the three auxiliary nodes
# in turn, so that picking any camera in Cheese works without re-powering.
#
# FAN53870's enable register (0x03) is a bitmask: the front script uses 0x65,
# the ultrawide 0x4a, the macro 0x50.  This script writes the union (0x7f) and
# every LDO voltage any of them needs, then brings up each sensor on its own
# I2C bus, each D-PHY on its own CSI port, and finally streams the three nodes.
set -u
FR=${1:-30}
ORD=${2:-123}
# NO_STREAM=1 stops after the D-PHY arms (step 8) and prints the read-only
# per-port status instead of streaming.  Streaming is the only step that can
# leave a v4l2-ctl stuck in D state (2026-10-10: /dev/video2 never returned and
# could not even be killed), so a bring-up check must be able to skip it.
NO_STREAM=${NO_STREAM:-0}
# settle time between the reset pulses and the first sensor register write
SETTLE=${SETTLE:-1.5}
N="nice -n 19"
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
I="i2ctransfer -y -f 11"

echo "=== zz_all_nodes: four cameras, three auxiliary nodes ==="
date
uptime

echo "--- 0. free the cameras ---"
# A camera app that already holds /dev/video0 makes `rmmod cam_cap` fail with
# "Module cam_cap is in use" - that aborted the boot-time run on 2026-10-11
# 21:20, when KDE's session restore had Kamoso open.  Kill every camera app,
# force the nodes free, then retry the unload a few times.
for a in cheese guvcview kamoso snapshot; do
	pkill -x "$a" 2>/dev/null && echo "  stopped $a"
done
sleep 1
fuser -k /dev/video0 /dev/video1 /dev/video2 /dev/video3 2>/dev/null
sleep 1
if grep -q '^cam_cap ' /proc/modules; then
	i=1
	while [ $i -le 3 ]; do
		rmmod cam_cap && break
		echo "  rmmod failed (attempt $i) - releasing the holders again"
		for a in cheese guvcview kamoso snapshot; do
			pkill -9 -x "$a" 2>/dev/null
		done
		fuser -k /dev/video0 /dev/video1 /dev/video2 /dev/video3 2>/dev/null
		sleep 2
		i=$((i + 1))
	done
	grep -q '^cam_cap ' /proc/modules && { echo "ABORT: rmmod failed after 3 attempts"; exit 1; }
fi
dmesg -c >/dev/null 2>&1

echo "--- 1. clean rail state ---"
$G 158 0 >/dev/null 2>&1
echo "GPIO150 func0" > $P/pinmux-select 2>/dev/null
echo "GPIO151 func0" > $P/pinmux-select 2>/dev/null
echo "GPIO162 func0" > $P/pinmux-select 2>/dev/null
$I w2@0x35 0x03 0x00 >/dev/null 2>&1
sleep 1

echo "--- 2. camera I2C4 controller (runtime overlay, for the macro) ---"
if [ ! -d /proc/device-tree/soc@0/i2c@11d03000 ]; then
	insmod /root/ovl_i2c4b.ko || echo "  WARN: overlay insmod failed"
	sleep 2
fi
dmesg | grep -iE 'ovl_i2c4' | tail -2

echo "--- 3. load the driver in multi-node mode ---"
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh 2>&1 | tail -2
CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh 2>&1 | tail -2
ls -l /dev/video* 2>&1

echo "--- 4. rails for all three auxiliary cameras (union mask 0x7f) ---"
for a in "0x04 0x89" "0x05 0x95" "0x06 0xbf" "0x07 0xb3" "0x08 0xb3" \
	"0x09 0xbf" "0x0a 0x36"; do
	$I w2@0x35 $a >/dev/null 2>&1 && echo "  ldo $a ok"
done
$I w2@0x35 0x03 0x7f >/dev/null 2>&1
sleep 0.3
echo "  fan 0x03=$($I w1@0x35 0x03 2>&1)"
$G 158 1 >/dev/null 2>&1
$G 144 1 >/dev/null 2>&1
echo "  vcam + dovdd switches high"

echo "--- 5. MCLK + I2C pads for every auxiliary camera ---"
echo "GPIO150 func1" > $P/pinmux-select 2>/dev/null	# front  -> CMMCLK0
echo "GPIO162 func1" > $P/pinmux-select 2>/dev/null	# uw     -> CMMCLK?
echo "GPIO151 func1" > $P/pinmux-select 2>/dev/null	# macro  -> CMMCLK1
echo "GPIO137 func1" > $P/pinmux-select 2>/dev/null	# macro SCL4
echo "GPIO138 func1" > $P/pinmux-select 2>/dev/null	# macro SDA4

echo "--- 6. reset pulses: front 153, ultrawide 156, macro 154 ---"
for p in 153 156 154; do
	$G $p 0 >/dev/null 2>&1
done
sleep 0.1
for p in 153 156 154; do
	$G $p 1 >/dev/null 2>&1
done
echo "  settle ${SETTLE}s before the first register write"
sleep "$SETTLE"

echo "--- 7. sensor tables ---"
echo "  front (i2c-8 @0x10)"
$N python3 /root/sensor_bring.py 8 0x10 /root/imx596_init.txt \
	/root/imx596_2592x1952.txt 2>&1 | tail -3
echo "  ultrawide (i2c-8 @0x2d)"
$N python3 /root/sensor_bring.py 8 0x2d /root/s5k4h7_init.txt \
	/root/s5k4h7_3264x2448.txt 2>&1 | tail -3
MBUS=""
for d in /dev/i2c-*; do
	b=${d#/dev/i2c-}
	id=$(timeout 5 i2ctransfer -y -f "$b" w1@0x37 0xf0 r1 2>/dev/null | head -1)
	if [ "$id" = "0x02" ]; then
		MBUS=$b
		echo "  macro bus: $d (0x37 f0=$id)"
		break
	fi
done
if [ -n "$MBUS" ]; then
	echo "  macro (i2c-$MBUS @0x37)"
	A8=1 $N python3 /root/sensor_bring.py $MBUS 0x37 /root/gc02m1_init.txt 2>&1 | tail -3
else
	echo "  WARN: macro GC02M1 did not answer on 0x37"
fi

echo "--- 7b. sensor ID read-back (did the tables land?) ---"
echo "  front i2c-8 @0x10 : $(timeout 5 i2ctransfer -y -f 8 w2@0x10 0x00 0x00 r2 2>&1 | head -1)"
echo "  uw    i2c-8 @0x2d : $(timeout 5 i2ctransfer -y -f 8 w2@0x2d 0x00 0x00 r2 2>&1 | head -1)"
if [ -n "$MBUS" ]; then
	echo "  macro i2c-$MBUS @0x37 : $(timeout 5 i2ctransfer -y -f "$MBUS" w1@0x37 0xf0 r1 2>&1 | head -1)"
fi

# Each auxiliary sensor needs its own register table pushed *again* after the
# reset settle: the combined bring-up's 1.5 s is too short for the ultrawide,
# which then answers on I2C but never starts transmitting (measured
# 2026-10-11: port 1 PKT stayed 0 / CLK_FSM 0x101 while the macro on port 3 was
# at 0x110 with packets).  Replaying the table later fixes it, and the
# ultrawide-alone script (zz_uw_node.sh) has always waited 3 s after reset.
# So: replay, stream, count frames, retry -- one camera at a time.
replay () {	# replay <node>
	case "$1" in
	1) $N python3 /root/sensor_bring.py 8 0x10 /root/imx596_init.txt \
		/root/imx596_2592x1952.txt >/dev/null 2>&1 ;;
	2) $N python3 /root/sensor_bring.py 8 0x2d /root/s5k4h7_init.txt \
		/root/s5k4h7_3264x2448.txt >/dev/null 2>&1 ;;
	3) [ -n "$MBUS" ] && A8=1 $N python3 /root/sensor_bring.py "$MBUS" 0x37 \
		/root/gc02m1_init.txt >/dev/null 2>&1 ;;
	esac
}

stream_once () {	# stream_once <node> : stream in the background, diagnose in front
	( timeout 14 v4l2-ctl -d /dev/video$1 --stream-mmap --stream-count=$FR \
		--stream-to=/root/aux_$1.yuyv >/tmp/zz_v$1.log 2>&1 ) &
	sp=$!
	sleep 9
	# The macro's analogue gain only latches while a stream is running on it
	# (measured 2026-10-11: written between bring-up and streaming it reads
	# back 0x06 but leaves the frame at 1.0x -- green mean 294, peak 674;
	# written *now* the same value takes the mean to 433 and the peak to 2012,
	# and it then survives later stream stop/start).  So apply it here, with
	# the macro on the wire, and give it two frames before the diagnosis.
	if [ "$1" = 3 ] && [ -n "${MBUS:-}" ]; then
		i2ctransfer -y -f "$MBUS" w2@0x37 0xf0 0x00 >/dev/null 2>&1
		i2ctransfer -y -f "$MBUS" w2@0x37 0xb6 0x06 >/dev/null 2>&1
		sleep 2
	fi
	grep -E '^(route|timing|avg|dist|stats)' /proc/camcap_info | head -5
	wait $sp 2>/dev/null
}

try_node () {	# try_node <node> : up to 3 (replay, stream) attempts
	i=1
	frames=0
	while [ "$i" -le 3 ]; do
		echo "  --- /dev/video$1, attempt $i"
		replay "$1"
		sleep 2
		stream_once "$1"
		frames=$(grep -E '^avg' /proc/camcap_info |
			sed -n 's/.*frames=\([0-9]*\).*/\1/p')
		[ "${frames:-0}" -gt 0 ] && break
		echo "      no frames yet, replays left: $((3 - i))"
		i=$((i + 1))
	done
	echo "  /dev/video$1: frames=${frames:-0} after attempt $i"
	echo "    log: $(tr '\n' ' ' < /tmp/zz_v$1.log)"
	sz=$(v4l2-ctl -d /dev/video$1 --get-fmt-video 2>/dev/null |
		sed -n 's/.*Size Image *: *\([0-9]*\).*/\1/p')
	# The driver's frame counter runs one ahead of what v4l2-ctl wrote (it
	# counted 21 for a --stream-count=20 run), so take the frame count from the
	# file itself: skipping the driver's number lands past EOF and yields 0 B.
	if [ -n "$sz" ]; then
		nf=$(($(stat -c %s /root/aux_$1.yuyv) / sz))
		if [ "$nf" -gt 0 ]; then
			dd if=/root/aux_$1.yuyv of=/root/aux_$1.last bs="$sz" \
				skip=$((nf - 1)) count=1 2>/dev/null
			echo "    last frame saved: /root/aux_$1.last ($sz B each, $nf frames in file)"
		fi
	fi
}

echo "--- 8. D-PHY links: front port 0, ultrawide port 1, macro port 3 ---"
for a in "0 678 3" "1 330 1" "3 336 3 1 92"; do
	echo "  csirx $a"
	$N python3 /root/csirx_bring.py $a 2>&1 | grep -E 'FINAL|PKT|TOP_PHY' | tail -2
done

echo "--- 8b. read-only status of all four CSI ports ---"
$N python3 /root/csirx_stat.py 2>&1

if [ "$NO_STREAM" = 1 ]; then
	echo "--- 9. skipped (NO_STREAM=1) ---"
else
echo "--- 9. each auxiliary node: replay its table, stream it, retry if empty (order $ORD) ---"
for node in $(echo "$ORD" | sed 's/\(.\)/\1 /g'); do
	try_node "$node"
done
fi

echo "--- 10. dmesg (cam_cap routes and registrations) ---"
dmesg | grep -E 'cam_cap: (route|v4l2: (registered|streaming|s_fmt))' | tail -20

echo "--- 11. health ---"
echo "timed out: $(dmesg | grep -c 'timed out')"
echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|watchdog|Unable to handle|Internal error')"
uptime
echo "=== done ==="
