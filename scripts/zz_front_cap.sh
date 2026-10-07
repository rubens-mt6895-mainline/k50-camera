#!/bin/sh
# zz_front_cap.sh [frames] [bin] [stride] - bring up the FRONT IMX596 end to end
# on CSI port 0 (SENINF intf 0, D-PHY 0x11c82000, i2c-8 @0x10) and capture.
#
# Wiring (from the PR's rubens.dts): vcam gpio158, reset gpio153, MCLK gpio150 ->
# CMMCLK0 (camtg), FAN53870 ldo1 dvdd 1.104V / ldo3 avdd 2.900V / ldo7 dovdd
# 1.804V, SPI/CSI on the 4D1C port 0.
set -u
FR=${1:-30}
BIN=${2:-1}
STRIDE=${3:-0}
N="nice -n 19"
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
I="i2ctransfer -f -y 11"
BUS=8
W=2592
H=1952
OW=$((W / BIN))
OH=$((H / BIN))

echo "=== zz_front_cap: IMX596 on CSI port 0 ($W x $H, bin $BIN) ==="
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

echo "--- 1. front camera rails (vcam + FAN53870 ldo1/3/7) ---"
$G 158 1 >/dev/null 2>&1
$I w2@0x35 0x0a 0x36 2>&1
$I w2@0x35 0x06 0xbf 2>&1
$I w2@0x35 0x04 0x89 2>&1
$I w2@0x35 0x03 0x65 2>&1
sleep 0.3
echo "  fan 0x03=$($I w1@0x35 0x03 r1 2>&1)"

echo "--- 2. front MCLK: GPIO150 -> CMMCLK0 ---"
echo "GPIO150 func1" > $P 2>/dev/null

echo "--- 3. reset pulse GPIO153 (low 50 ms -> high) ---"
$G 153 0 >/dev/null 2>&1
sleep 0.05
$G 153 1 >/dev/null 2>&1
sleep 0.05

echo "--- 4. IMX596 init + 2592x1952 tables (i2c-$BUS @0x10) ---"
$N python3 /root/sensor_bring.py $BUS 0x10 /root/imx596_init.txt /root/imx596_2592x1952.txt 2>&1 | tail -32

echo "--- 5. CSI RX port 0 (link 678 MHz) ---"
$N python3 /root/csirx_bring.py 0 678 3 2>&1 | tail -42

echo "--- 6. load cam_cap for the front camera ---"
ARGS="v4l2_enable=1 conv_threads=8 pipeline=1"
ARGS="$ARGS route_intf=0 dphy_base=0x11c82000 route_mux=1 cammux=3"
ARGS="$ARGS exp_hsize=$W exp_vsize=$H out_width=$OW out_height=$OH v4l2_bin=$BIN"
ARGS="$ARGS i2c_bus=$BUS i2c_addr=0x10 ae_enable=0 awb_enable=0"
if [ "$STRIDE" != "0" ]; then
	ARGS="$ARGS v4l2_src_stride=$STRIDE"
fi
insmod /root/cam_cap.ko $ARGS || { echo "ABORT: insmod failed"; exit 1; }
sleep 1
dmesg | grep -E 'cam_cap: (source|mode|output|route|rx|iommu|buffer|convert|v4l2: registered)' | tail -22

echo "--- 7. route + formats ---"
echo route > /proc/camcap
sleep 0.2
dmesg | grep -E 'cam_cap: route' | tail -14
v4l2-ctl -d /dev/video0 --list-formats 2>&1 | head -10

echo "--- 8. capture $FR frames ---"
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$FR --stream-to=/dev/null 2>&1 | tail -6

echo "--- 9. counters ---"
grep -E '^(source|mode|output|avg|timing|dist|stats|ae|awb|af|frame_ready|last_result|int_status|pkt|route|cam_mux|vf_on|buffer)' /proc/camcap_info 2>/dev/null | head -32

echo "--- 10. CSI2 pkt counter, intf 0 (0x1a010adc) ---"
busybox devmem 0x1a010adc 2>/dev/null
sleep 1
busybox devmem 0x1a010adc 2>/dev/null

echo "--- 11. health ---"
echo "crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog|Unable to handle')"
free | head -2
uptime
echo "=== done ==="
