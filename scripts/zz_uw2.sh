#!/bin/sh
# zz_uw2.sh - ultrawide (S5K4H7, intf 2 / csi1) capture with the frame saved for
# inspection; enables the SENINF mux frame-size monitor before streaming.
set -u
PB=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
I11="i2ctransfer -f -y 11"
G=/root/gpiotoolG
d32() { busybox devmem "$1" 32; }
w32() { busybox devmem "$1" 32 "$2"; }

free_cam() {
	pkill -x cheese 2>/dev/null
	sleep 1
	fuser -k /dev/video0 2>/dev/null
	sleep 1
	rmmod cam_cap 2>/dev/null
	sleep 1
}

echo "=== rails ==="
for a in "0x04 0x89" "0x05 0x95" "0x06 0xbf" "0x07 0xb3" "0x08 0xb3" "0x09 0xbf" "0x0a 0x36"; do
	$I11 w2@0x35 $a >/dev/null 2>&1 && echo "  ldo $a ok"
done
$I11 w2@0x35 0x03 0x4a >/dev/null 2>&1; echo "  enable 0x4a"
$G 158 1 >/dev/null 2>&1; echo "  vcam high"
echo "GPIO162 func1" > $PB
$G 156 0 >/dev/null 2>&1; sleep 1; $G 156 1 >/dev/null 2>&1; sleep 3

echo "=== sensor firmware ==="
python3 /root/sensor_bring.py 8 0x2d /root/s5k4h7_init.txt /root/s5k4h7_3264x2448.txt 2>&1 | tail -6
echo "=== csi rx (csi1, 330 MHz DDR) ==="
python3 /root/csirx_bring.py 1 330 1 2>&1 | tail -8

free_cam
echo "=== insmod (3264x2448) ==="
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=8 pipeline=1 route_intf=2 dphy_base=0x11c92000 \
	route_mux=1 cammux=3 exp_hsize=3264 exp_vsize=2448 out_width=3264 out_height=2448 \
	v4l2_bin=1 i2c_bus=8 i2c_addr=0x2d ae_enable=0 awb_enable=0 exp_def=2000 exp_max=2400 2>&1 | tail -3
sleep 1
echo "  monitor: $(w32 0x1a011da8 1) $(d32 0x1a011da8)"
echo "  TOP_MUX = $(d32 0x1a010010)  CAM_MUX3 = $(d32 0x1a010460) chk_ctl=$(d32 0x1a010468)"
echo "=== stream 3 frames to /root/uw.yuyv ==="
timeout 30 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=3 --stream-to=/root/uw.yuyv 2>&1 | tail -3
echo "  uw.yuyv: $(ls -l /root/uw.yuyv 2>/dev/null | awk '{print $5}') bytes"
echo "  monitor H_valid=$(d32 0x1a011db0) H_blank=$(d32 0x1a011db4)"
grep -E '^(source|output|v4l2: registered)' /proc/camcap_info
grep -E '^(avg|timing|dist|stats|ae)' /proc/camcap_info
echo "  counters: $(grep -E 'frame_ready|last_result|arm_count|cam_mux_chk' /proc/camcap_info | tr -d ' ' | tr '\n' ' ')"
echo "=== dmesg (cam_cap) ==="
dmesg | grep -E 'cam_cap: (route|rx|arm|mode|pipeline)' | tail -8
echo "=== zz_uw2 done ==="
