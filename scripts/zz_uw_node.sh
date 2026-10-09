#!/bin/sh
# Stream the ULTRAWIDE S5K4H7 through its own video node (/dev/video2) while the
# driver stays loaded in multi-node mode.  Bring-up (rails, MCLK, reset, sensor
# tables, D-PHY link) is userspace work; the driver only switches the route to
# CSI port 1 and converts.
#
# Order matters: loading the main camera's stack (zz_v80.sh / zz_cam_up.sh)
# writes FAN53870, so the auxiliary camera's rails must be programmed *after*
# the driver is loaded, or the sensor loses power before it can send frames.
set -u
FR=${1:-30}
N="nice -n 19"
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
I="i2ctransfer -f -y 11"
BUS=8

echo "=== zz_uw_node: S5K4H7 -> /dev/video2, $FR frames ==="
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
echo "GPIO150 func0" > $P 2>/dev/null
$I w2@0x35 0x03 0x00 >/dev/null 2>&1
sleep 1

echo "--- 2. load the driver in multi-node mode ---"
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh 2>&1 | tail -2
CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh 2>&1 | tail -2
ls -l /dev/video* 2>&1

echo "--- 3. ultrawide rails (last writer of FAN53870) ---"
for a in "0x04 0x89" "0x05 0x95" "0x06 0xbf" "0x07 0xb3" "0x08 0xb3" \
	"0x09 0xbf" "0x0a 0x36"; do
	$I w2@0x35 $a >/dev/null 2>&1 && echo "  ldo $a ok"
done
$I w2@0x35 0x03 0x4a >/dev/null 2>&1; echo "  enable 0x4a"
$G 158 1 >/dev/null 2>&1; echo "  vcam high"
echo "GPIO162 func1" > $P 2>/dev/null
$G 156 0 >/dev/null 2>&1
sleep 1
$G 156 1 >/dev/null 2>&1
sleep 3

echo "--- 4. S5K4H7 tables (i2c-$BUS @0x2d) ---"
$N python3 /root/sensor_bring.py $BUS 0x2d /root/s5k4h7_init.txt \
	/root/s5k4h7_3264x2448.txt 2>&1 | tail -6

echo "--- 5. CSI RX port 1, 330 MHz DDR ---"
$N python3 /root/csirx_bring.py 1 330 1 2>&1 | tail -6

echo "--- 6. node 2 before streaming ---"
timeout 10 v4l2-ctl -d /dev/video2 --info 2>&1 | grep -E 'Card type'
timeout 10 v4l2-ctl -d /dev/video2 --get-fmt-video 2>&1 |
	grep -E 'Width/Height|Bytes per Line|Size Image'

echo "--- 7. stream /dev/video2: $FR frames ---"
timeout 40 v4l2-ctl -d /dev/video2 --stream-mmap --stream-count=$FR \
	--stream-to=/dev/null 2>&1 | tail -5

echo "--- 8. counters ---"
grep -E '^(source|mode|output|avg|timing|dist|stats|frame_ready|last_result|int_status|route|cam_mux|vf_on|buffer)' /proc/camcap_info 2>/dev/null | head -24

echo "--- 9. dmesg (cam_cap) ---"
dmesg | grep -E 'cam_cap: (route|rx|source|output|mode|v4l2: (registered|streaming|s_fmt))' | tail -16

echo "--- 10. health ---"
echo "timed out: $(dmesg | grep -c 'timed out')"
echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|watchdog|Unable to handle|Internal error')"
uptime
echo "=== done ==="
