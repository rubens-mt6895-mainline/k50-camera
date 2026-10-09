#!/bin/sh
# Stream the FRONT IMX596 through its own video node (/dev/video1) while the
# driver stays loaded in multi-node mode.  Rails, MCLK, reset, the sensor's
# register tables and the D-PHY link are userspace bring-up (the driver has no
# sensor driver for the auxiliary cameras); the driver only switches the route
# to CSI port 0 and converts the frames.
set -u
FR=${1:-30}
N="nice -n 19"
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
I="i2ctransfer -f -y 11"
BUS=8

echo "=== zz_front_node: IMX596 -> /dev/video1, $FR frames ==="
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

echo "--- 1. load in multi-node mode ---"
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh >/dev/null 2>&1
CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh >/dev/null 2>&1
ls -l /dev/video* 2>&1

echo "--- 2. front rails (vcam gpio158 + FAN53870 ldo1/3/7) ---"
$G 158 1 >/dev/null 2>&1
$I w2@0x35 0x0a 0x36 2>&1
$I w2@0x35 0x06 0xbf 2>&1
$I w2@0x35 0x04 0x89 2>&1
$I w2@0x35 0x03 0x65 2>&1
sleep 0.3
echo "  fan 0x03=$($I w1@0x35 0x03 r1 2>&1)"

echo "--- 3. MCLK gpio150 -> CMMCLK0, reset gpio153 ---"
echo "GPIO150 func1" > $P 2>/dev/null
$G 153 0 >/dev/null 2>&1
sleep 0.05
$G 153 1 >/dev/null 2>&1
sleep 0.05

echo "--- 4. IMX596 tables (i2c-$BUS @0x10) ---"
$N python3 /root/sensor_bring.py $BUS 0x10 /root/imx596_init.txt /root/imx596_2592x1952.txt 2>&1 | tail -12

echo "--- 5. CSI RX port 0, link 678 MHz ---"
$N python3 /root/csirx_bring.py 0 678 3 2>&1 | tail -12

echo "--- 6. node 1 before streaming ---"
timeout 10 v4l2-ctl -d /dev/video1 --info 2>&1 | grep -E 'Card type'
timeout 10 v4l2-ctl -d /dev/video1 --get-fmt-video 2>&1 |
	grep -E 'Width/Height|Bytes per Line|Size Image'

echo "--- 7. stream /dev/video1: $FR frames ---"
timeout 40 v4l2-ctl -d /dev/video1 --stream-mmap --stream-count=$FR \
	--stream-to=/dev/null 2>&1 | tail -5

echo "--- 8. counters ---"
grep -E '^(source|mode|output|avg|timing|dist|stats|frame_ready|last_result|int_status|route|cam_mux|vf_on|buffer)' /proc/camcap_info 2>/dev/null | head -24

echo "--- 9. dmesg (cam_cap) ---"
dmesg | grep -E 'cam_cap: (route|rx|source|output|mode|v4l2: (registered|streaming|s_fmt))' | tail -16

echo "--- 10. health ---"
echo "timed out: $(dmesg | grep -c 'timed out')"
echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|watchdog|Unable to handle|Internal error')"
free | head -2
uptime
echo "=== done ==="
