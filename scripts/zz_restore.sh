#!/bin/sh
# zz_restore.sh - leave the camera on the default configuration (preview 4000x3000
# binned to 2000x1500, mode_trace off, conv_threads 4) after a test run, and show
# what the driver reports at load time.
set -u
W=/dev/video0

pkill -x cheese 2>/dev/null
fuser -k $W 2>/dev/null
sleep 0.5
rmmod cam_cap 2>/dev/null
sleep 0.5
dmesg -c >/dev/null 2>&1

MODE_W=4000 MODE_H=3000 MODE_STRIDE=6000 MODE_FRAME=18874368 \
	sh /root/zz_v80.sh 2>&1 | grep -E 'IMX582 (ALIVE|DEAD)|frame_ready'
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=4 pipeline=1" \
	sh /root/zz_cam_up.sh 2>&1 | grep -E '\[!!\]|registered|streaming|source:|output:|mode:'
sleep 1

echo "--- load-time driver lines ---"
dmesg | grep -E 'cam_cap: (source|mode|output|v4l2: registered)' | sed 's/^/  /'

echo "--- sensor ---"
echo "  0307=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x07 r1 2>&1) 0900=$(i2ctransfer -f -y 10 w2@0x10 0x09 0x00 r1 2>&1) 0340=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x40 r1 2>&1) 0341=$(i2ctransfer -f -y 10 w2@0x10 0x03 0x41 r1 2>&1)"

echo "--- 30 frame check ---"
timeout 20 v4l2-ctl -d $W --stream-mmap --stream-count=30 --stream-to=/dev/null >/dev/null 2>&1
grep -E '^(avg|timing|dist|stats|ae)' /proc/camcap_info 2>/dev/null | sed 's/^/  /'

echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
uptime
echo "### zz_restore done"
