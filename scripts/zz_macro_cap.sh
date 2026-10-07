#!/bin/sh
# zz_macro_cap.sh [frames] [bin] - bring up the MACRO GC02M1 end to end.
#
# The macro camera hangs off the camera I2C4 controller at 0x11d03000, which our
# device tree does not describe: the ovl_i2c4b overlay module adds it at runtime
# (see dt/ovl_i2c4.dts and scripts/z_build_ovl6.sh), which is why the bus shows
# up with a dynamic minor (i2c-12 today) instead of i2c-4.
#
# Wiring: FAN53870 l5 avdd 2.804V, l7 dovdd 1.804V, dovdd switch gpio144,
# vcam gpio158, MCLK gpio151 -> CMMCLK1, I2C pads gpio137/138 -> SCL4/SDA4,
# reset gpio154 (active low), single CSI lane on port 3 (SENINF intf 6,
# D-PHY 0x11c96000, link 336 MHz, hs-trail-ps 92000).
set -u
FR=${1:-30}
BIN=${2:-1}
N="nice -n 19"
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
I="i2ctransfer -y -f 11"
W=1600
H=1200
OW=$((W / BIN))
OH=$((H / BIN))

echo "=== zz_macro_cap: GC02M1 on CSI port 3 ($W x $H, bin $BIN) ==="
date
uptime

echo "--- 0. free the camera ---"
pkill -x cheese 2>/dev/null
pkill -x guvcview 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
if grep -q '^cam_cap' /proc/modules; then
	rmmod cam_cap 2>&1 || { echo "ABORT: cam_cap still loaded"; exit 1; }
fi
dmesg -c >/dev/null 2>&1
echo "  cam_cap unloaded"

echo "--- 1. camera I2C4 controller (runtime overlay) ---"
if [ ! -d /proc/device-tree/soc@0/i2c@11d03000 ]; then
	insmod /root/ovl_i2c4b.ko || { echo "ABORT: overlay insmod failed"; exit 1; }
	sleep 2
fi
dmesg | grep -iE 'ovl_i2c4' | tail -3

echo "--- 2. macro rails ---"
$G 158 1 >/dev/null 2>&1
$G 144 1 >/dev/null 2>&1
$I w2@0x35 0x08 0xb3 2>&1
$I w2@0x35 0x0a 0x36 2>&1
$I w2@0x35 0x03 0x50 2>&1
sleep 0.3
echo "  fan 0x03=$($I w1@0x35 0x03 2>&1)"

echo "--- 3. macro MCLK (GPIO151 -> CMMCLK1) + I2C pads (137/138) ---"
echo "GPIO151 func1" > $P/pinmux-select 2>/dev/null
echo "GPIO137 func1" > $P/pinmux-select 2>/dev/null
echo "GPIO138 func1" > $P/pinmux-select 2>/dev/null

echo "--- 4. reset pulse GPIO154 (low 50 ms -> high) ---"
$G 154 0 >/dev/null 2>&1
sleep 0.05
$G 154 1 >/dev/null 2>&1
sleep 0.1

echo "--- 5. find the macro bus and read the chip id ---"
BUS=""
for d in /dev/i2c-*; do
	b=${d#/dev/i2c-}
	id=$(timeout 5 i2ctransfer -y -f "$b" w1@0x37 0xf0 r1 2>/dev/null | head -1)
	if [ "$id" = "0x02" ]; then
		BUS=$b
		echo "  $d @0x37: 0xf0=$id"
		break
	fi
done
[ -n "$BUS" ] || { echo "ABORT: GC02M1 did not answer 0x02f0"; exit 1; }

echo "--- 6. GC02M1 init table (8-bit registers, i2c-$BUS @0x37) ---"
A8=1 $N python3 /root/sensor_bring.py $BUS 0x37 /root/gc02m1_init.txt 2>&1 | tail -24

echo "--- 7. CSI RX port 3 (link 336 MHz, 1 lane, trail 92000 ps) ---"
$N python3 /root/csirx_bring.py 3 336 3 1 92 2>&1 | tail -40

echo "--- 8. load cam_cap for the macro camera ---"
ARGS="v4l2_enable=1 conv_threads=8 pipeline=1"
ARGS="$ARGS route_intf=6 dphy_base=0x11c96000 route_mux=1 cammux=3"
ARGS="$ARGS exp_hsize=$W exp_vsize=$H out_width=$OW out_height=$OH v4l2_bin=$BIN"
ARGS="$ARGS i2c_bus=$BUS i2c_addr=0x37 ae_enable=0 awb_enable=0"
insmod /root/cam_cap.ko $ARGS || { echo "ABORT: insmod failed"; exit 1; }
sleep 1
dmesg | grep -E 'cam_cap: (source|mode|output|route|rx|iommu|buffer|convert|v4l2: registered)' | tail -22

echo "--- 9. route + formats ---"
echo route > /proc/camcap
sleep 0.2
dmesg | grep -E 'cam_cap: route' | tail -14
v4l2-ctl -d /dev/video0 --list-formats 2>&1 | head -10

echo "--- 10. capture $FR frames ---"
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$FR --stream-to=/dev/null 2>&1 | tail -6

echo "--- 11. counters ---"
grep -E '^(source|mode|output|avg|timing|dist|stats|ae|awb|af|frame_ready|last_result|int_status|pkt|route|cam_mux|vf_on|buffer)' /proc/camcap_info 2>/dev/null | head -32

echo "--- 12. CSI2 pkt counter, intf 6 (0x1a016adc) ---"
busybox devmem 0x1a016adc 2>/dev/null
sleep 1
busybox devmem 0x1a016adc 2>/dev/null

echo "--- 13. health ---"
echo "crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog|Unable to handle')"
free | head -2
uptime
echo "=== done ==="
