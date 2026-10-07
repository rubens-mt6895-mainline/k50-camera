#!/bin/sh
# zz_sfmt.sh [frames] - exercise VIDIOC_S_FMT / VIDIOC_S_PARM end to end.
#
# The point of the exercise is that the driver now picks and replays a vendor
# sensor mode by itself: one module load, then applications change format with
# the standard V4L2 calls instead of the stack being torn down and brought back
# up in another mode.  Each step prints the resulting format, the driver's own
# log line, the measured frame rate and the frame statistics.
#
# One device task at a time (m00471).  zz_ctrl_run.sh pushes this script with
# zz_v80.sh / zz_cam_up.sh, which are the same bring-up steps cam_boot.sh uses.
set -u
NF=${1:-60}
W=/dev/video0

fps() {
	out=$(nice -n 10 timeout 25 v4l2-ctl -d $W --stream-mmap --stream-count=$NF \
		--stream-to=/dev/null 2>&1 | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1)
	echo "  rate: ${out:-NO FRAMES}"
}
info() {
	grep -E '^(avg|stats|ae)' /proc/camcap_info 2>/dev/null | sed 's/^/  /'
}
dshow() {
	dmesg | grep -E 'cam_cap: (mode|source|rx)|s_fmt|s_parm|no table' | sed 's/^/  /'
}

echo "--- 0. free the camera ---"
pgrep -x cheese >/dev/null 2>&1 && { pkill -x cheese; sleep 2; }
fuser -k $W 2>/dev/null
sleep 0.5

echo "--- 1. clean module state ---"
if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap 2>&1 | sed 's/^/  /'
fi
if grep -q '^cam_cap ' /proc/modules; then echo "  [!!] cam_cap still loaded, ABORT"; exit 1; fi
echo "  [ok] cam_cap not loaded"

echo "--- 2. sensor bring-up, preview table (same as cam_boot.sh) ---"
MODE_W=4000 MODE_H=3000 MODE_STRIDE=6000 MODE_FRAME=18874368 \
	sh /root/zz_v80.sh 2>&1 | tail -6

echo "--- 3. load the module with the default geometry ---"
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=8 pipeline=1" \
	sh /root/zz_cam_up.sh 2>&1 | tail -10
sleep 1

echo "--- 4. the mode table the driver carries ---"
dmesg -c >/dev/null
echo "modes" > /proc/camcap
sleep 0.3
dmsg=$(dmesg); echo "$dmsg" | grep -E 'cam_cap: mode[0-9]' | sed 's/^/  /'

echo "--- 5. what an application sees ---"
nice -n 10 v4l2-ctl -d $W --list-formats-ext 2>&1 | head -30

echo "--- 6. A) default geometry, 2000x1500 preview binned ---"
dshow
fps
info

echo "--- 7. B) S_FMT 1920x1080 (expect custom2, 120 fps sensor mode) ---"
dmesg -c >/dev/null
nice -n 10 v4l2-ctl -d $W -v width=1920,height=1080 2>&1 | grep -E 'Width|Height|Pixel'
sleep 0.5
dshow
fps
info

echo "--- 8. C) S_PARM 240 fps on the same size (expect hs_video) ---"
dmesg -c >/dev/null
nice -n 10 v4l2-ctl -d $W --set-parm=240 2>&1
nice -n 10 v4l2-ctl -d $W --get-parm 2>&1 | grep -E 'fps|Streaming'
sleep 0.5
dshow
fps
info

echo "--- 9. D) S_PARM 120 fps back to the other 1080p table ---"
dmesg -c >/dev/null
nice -n 10 v4l2-ctl -d $W --set-parm=120 2>&1
sleep 0.5
dshow
fps
info

echo "--- 10. E) S_FMT 4000x2256 (expect normal_video, 30 fps table) ---"
dmesg -c >/dev/null
nice -n 10 v4l2-ctl -d $W -v width=4000,height=2256 2>&1 | grep -E 'Width|Height|Pixel'
sleep 0.5
dshow
fps
info

echo "--- 11. F) S_PARM 60 fps on 4000x2256 (expect custom3) ---"
dmesg -c >/dev/null
nice -n 10 v4l2-ctl -d $W --set-parm=60 2>&1
sleep 0.5
dshow
fps
info

echo "--- 12. G) back to 2000x1500, the format Cheese asks for ---"
dmesg -c >/dev/null
nice -n 10 v4l2-ctl -d $W -v width=2000,height=1500 2>&1 | grep -E 'Width|Height|Pixel'
sleep 0.5
dshow
fps
info

echo "--- 13. H) 4000x2256 at 60 fps through /proc (binned converter) ---"
dmesg -c >/dev/null
echo "mode custom3 2" > /proc/camcap
sleep 0.5
dshow
nice -n 10 v4l2-ctl -d $W --get-fmt-video 2>&1 | grep -E 'Width|Height'
fps
info

echo "--- 14. health ---"
echo "  crashes: $(dmesg | grep -icE 'oops|call trace|panic')"
free -m | head -2
uptime
echo "### zz_sfmt done"
