#!/bin/sh
# The capture buffer holds what exp_hsize x exp_vsize needs at load time; a mode
# whose raw frame is larger must be refused, not selected.  Load for 4000x2256
# (13.6 MB) and ask for 4000x3000 (18 MB) through S_FMT.
set -u
D=/dev/video0

echo "### A) normal_video geometry: 4000x2256 -> 13.6 MB buffer"
pgrep -x cheese >/dev/null 2>&1 && { pkill -x cheese; sleep 2; }
fuser -k $D 2>/dev/null
if grep -q '^cam_cap ' /proc/modules; then rmmod cam_cap; fi
if grep -q '^cam_cap ' /proc/modules; then echo "  [!!] cam_cap still loaded, ABORT"; exit 1; fi
IMX582_MODE=normal_video MODE_W=4000 MODE_H=2256 MODE_STRIDE=6000 MODE_FRAME=13631488 \
	sh /root/zz_v80.sh >/dev/null 2>&1
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=2256 out_width=2000 out_height=1128 exp_max=3530 conv_threads=8 v4l2_bin=2" \
	sh /root/zz_cam_up.sh >/dev/null 2>&1
md5sum /root/cam_cap.ko
dmesg | grep -E 'source:|output:|registered /dev/video0' | tail -3
echo "--- current format ---"
v4l2-ctl -d $D -V 2>&1 | grep -E 'Width/Height'
echo "--- frame sizes the driver offers ---"
v4l2-ctl -d $D --list-framesizes=YUYV 2>&1 | grep -E 'Discrete' | tr -s ' '
echo "--- ask for 4000x3000 (needs 18000000 raw bytes) ---"
v4l2-ctl -d $D --set-fmt-video=width=4000,height=3000,pixelformat=YUYV >/dev/null 2>&1
v4l2-ctl -d $D -V 2>&1 | grep -E 'Width/Height'
dmesg | grep -E 'does not fit|needs .* raw bytes' | tail -2
echo "--- 60 frames must still run the 4000x2256 mode ---"
timeout 40 v4l2-ctl -d $D --stream-mmap --stream-count=60 --stream-to=/dev/null >/dev/null 2>&1
grep -E '^(timing|avg|dist)' /proc/camcap_info | cut -c1-140
echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|Unable to handle|Internal error')"

echo
echo "### B) back to the default 4000x3000 geometry"
sh /root/zz_restore.sh >/dev/null 2>&1
md5sum /root/cam_cap.ko
v4l2-ctl -d $D -V 2>&1 | grep -E 'Width/Height'
echo "--- frame sizes offered again ---"
v4l2-ctl -d $D --list-framesizes=YUYV 2>&1 | grep -E 'Discrete' | tr -s ' '
echo "--- 80 frames on the default stack ---"
timeout 40 v4l2-ctl -d $D --stream-mmap --stream-count=80 --stream-to=/dev/null >/dev/null 2>&1
grep -E '^(timing|avg|dist|stats)' /proc/camcap_info | cut -c1-140
echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|Unable to handle|Internal error')"
echo "load: $(cut -d' ' -f1-3 /proc/loadavg)"
