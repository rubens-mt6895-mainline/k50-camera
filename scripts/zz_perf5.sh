#!/bin/sh
# zz_perf5.sh <threads> <frames> - one measurement point of the convert pool.
NTH=${1:-1}
NFR=${2:-20}

for p in cheese gst-launch-1.0 ffmpeg; do
	n=$(pgrep -c -x "$p" 2>/dev/null); [ -z "$n" ] && n=0
	[ "$n" != 0 ] && echo "!! $p running ($n)"
done

pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>&1
sleep 1
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=$NTH 2>&1
rc=$?
echo "insmod rc=$rc conv_threads=$NTH frames=$NFR"
[ "$rc" != 0 ] && exit 1
sleep 2

timeout 120 nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$NFR --stream-to=/dev/null 2>&1 | tail -2
echo "v4l2-ctl rc=$?"

grep -E 'convert|timing|avg|stats' /proc/camcap_info
echo "--- dmesg (module lines + crash scan) ---"
dmesg | grep -E 'cam_cap: (convert|v4l2|route: mux)' | tail -4
echo -n "crash lines this boot: "
dmesg | grep -c -E 'Oops|paging request|BUG: unable' 
uptime
