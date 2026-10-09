#!/bin/sh
# Stream the MACRO GC02M1 through its own video node (/dev/video3) while the
# driver stays loaded in multi-node mode.  Bring-up is the same userspace
# sequence as zz_macro_cap.sh: runtime I2C4 overlay, rails, MCLK, I2C pads,
# reset, sensor init table, D-PHY link on CSI port 3.
#
# FAN53870 is written by the main camera's stack during load, so the macro's
# rails go on *after* the driver is loaded.
set -u
FR=${1:-30}
N="nice -n 19"
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
I="i2ctransfer -y -f 11"

echo "=== zz_macro_node: GC02M1 -> /dev/video3, $FR frames ==="
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

echo "--- 1. drop the previous camera's rail/clock state ---"
$G 158 0 >/dev/null 2>&1
echo "GPIO150 func0" > $P/pinmux-select 2>/dev/null
$I w2@0x35 0x03 0x00 >/dev/null 2>&1
sleep 1

echo "--- 2. camera I2C4 controller (runtime overlay) ---"
if [ ! -d /proc/device-tree/soc@0/i2c@11d03000 ]; then
	insmod /root/ovl_i2c4b.ko || { echo "ABORT: overlay insmod failed"; exit 1; }
	sleep 2
fi
dmesg | grep -iE 'ovl_i2c4' | tail -3

echo "--- 3. load the driver in multi-node mode ---"
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh 2>&1 | tail -2
CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh 2>&1 | tail -2
ls -l /dev/video* 2>&1

echo "--- 4. macro rails (last writer of FAN53870) ---"
$G 158 1 >/dev/null 2>&1
$G 144 1 >/dev/null 2>&1
$I w2@0x35 0x08 0xb3 2>&1
$I w2@0x35 0x0a 0x36 2>&1
$I w2@0x35 0x03 0x50 2>&1
sleep 0.3
echo "  fan 0x03=$($I w1@0x35 0x03 2>&1)"

echo "--- 5. MCLK gpio151 -> CMMCLK1, I2C pads gpio137/138 ---"
echo "GPIO151 func1" > $P/pinmux-select 2>/dev/null
echo "GPIO137 func1" > $P/pinmux-select 2>/dev/null
echo "GPIO138 func1" > $P/pinmux-select 2>/dev/null
$G 154 0 >/dev/null 2>&1
sleep 0.05
$G 154 1 >/dev/null 2>&1
sleep 0.1

echo "--- 6. find the macro bus (0x37 f0 = 0x02) ---"
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

echo "--- 7. GC02M1 init table (8-bit regs, i2c-$BUS @0x37) ---"
A8=1 $N python3 /root/sensor_bring.py $BUS 0x37 /root/gc02m1_init.txt 2>&1 | tail -10

echo "--- 8. CSI RX port 3 (336 MHz, 1 lane, trail 92000 ps) ---"
$N python3 /root/csirx_bring.py 3 336 3 1 92 2>&1 | tail -8

echo "--- 9. node 3 before streaming ---"
timeout 10 v4l2-ctl -d /dev/video3 --info 2>&1 | grep -E 'Card type'
timeout 10 v4l2-ctl -d /dev/video3 --get-fmt-video 2>&1 |
	grep -E 'Width/Height|Bytes per Line|Size Image'

echo "--- 10. stream /dev/video3: $FR frames ---"
timeout 40 v4l2-ctl -d /dev/video3 --stream-mmap --stream-count=$FR \
	--stream-to=/dev/null 2>&1 | tail -5

echo "--- 11. counters ---"
grep -E '^(source|mode|output|avg|timing|dist|stats|frame_ready|last_result|int_status|route|cam_mux|vf_on|buffer)' /proc/camcap_info 2>/dev/null | head -24

echo "--- 12. dmesg (cam_cap) ---"
dmesg | grep -E 'cam_cap: (route|rx|source|output|mode|v4l2: (registered|streaming|s_fmt))' | tail -16

echo "--- 13. health ---"
echo "timed out: $(dmesg | grep -c 'timed out')"
echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|watchdog|Unable to handle|Internal error')"
uptime
echo "=== done ==="
