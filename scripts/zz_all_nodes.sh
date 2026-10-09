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
N="nice -n 19"
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
I="i2ctransfer -y -f 11"

echo "=== zz_all_nodes: four cameras, three auxiliary nodes ==="
date
uptime

echo "--- 0. free the cameras ---"
pkill -x cheese 2>/dev/null
pkill -x guvcview 2>/dev/null
sleep 1
if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap || { echo "ABORT: rmmod failed"; exit 1; }
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
sleep 1.5

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

echo "--- 8. D-PHY links: front port 0, ultrawide port 1, macro port 3 ---"
for a in "0 678 3" "1 330 1" "3 336 3 1 92"; do
	echo "  csirx $a"
	$N python3 /root/csirx_bring.py $a 2>&1 | grep -E 'FINAL|PKT|TOP_PHY' | tail -2
done

echo "--- 9. stream each auxiliary node in turn (order: $ORD) ---"
for node in $(echo "$ORD" | sed 's/\(.\)/\1 /g'); do
	echo "  --- /dev/video$node"
	timeout 40 v4l2-ctl -d /dev/video$node --stream-mmap --stream-count=$FR \
		--stream-to=/dev/null 2>&1 | tail -2
	grep -E '^(avg|timing|dist|stats)' /proc/camcap_info | head -4
done

echo "--- 10. dmesg (cam_cap routes and registrations) ---"
dmesg | grep -E 'cam_cap: (route|v4l2: (registered|streaming|s_fmt))' | tail -20

echo "--- 11. health ---"
echo "timed out: $(dmesg | grep -c 'timed out')"
echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|watchdog|Unable to handle|Internal error')"
uptime
echo "=== done ==="
