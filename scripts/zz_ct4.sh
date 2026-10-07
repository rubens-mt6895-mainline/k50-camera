#!/bin/sh
# zz_ct4.sh [frames] - does a deeper pipeline (4 slots) or fewer convert threads
# recover the ~2 ms the CAMSV arm loses to converter CPU contention at native size?
#
# For each (conv_threads, pipe_slots) pair: reload, then stream the two native
# high-rate modes and report avg/timing/dist.
set -u
NF=${1:-120}
P=/sys/module/cam_cap/parameters
I=/proc/camcap_info

show() {
	grep -E '^(avg|timing|dist)' $I | sed 's/^/  /'
}

run_cfg() {
	TH=$1
	SL=$2
	echo
	echo "======== conv_threads=$TH pipe_slots=$SL ========"
	pkill -x cheese 2>/dev/null
	sleep 1
	fuser -k /dev/video0 2>/dev/null
	sleep 1
	if grep -q '^cam_cap ' /proc/modules; then
		rmmod cam_cap 2>&1 || { echo "ABORT: cam_cap in use"; return 1; }
	fi
	dmesg -c >/dev/null
	insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=$TH pipe_slots=$SL pipeline=1 || {
		echo "ABORT: insmod failed"; return 1; }
	echo 0 > $P/af_enable
	dmesg | grep -E 'pipeline: frame buffer|register' | sed 's/^/  /'

	# custom3 native 4000x2256 @60
	timeout 20 v4l2-ctl -d /dev/video0 -v width=4000,height=2256 >/dev/null 2>&1
	timeout 20 v4l2-ctl -d /dev/video0 --set-parm=60 >/dev/null 2>&1
	timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$NF >/dev/null 2>&1
	echo "  --- custom3 4000x2256 @60"; show

	# custom2 native 1920x1080 @120
	timeout 20 v4l2-ctl -d /dev/video0 -v width=1920,height=1080 >/dev/null 2>&1
	timeout 20 v4l2-ctl -d /dev/video0 --set-parm=120 >/dev/null 2>&1
	timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$NF >/dev/null 2>&1
	echo "  --- custom2 1920x1080 @120"; show
}

run_cfg 8 3
run_cfg 6 4
run_cfg 8 4

echo
echo "=== restore preview bin2 ==="
if grep -q '^cam_cap ' /proc/modules; then
	rmmod cam_cap 2>&1
fi
dmesg -c >/dev/null
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=4 pipeline=1
echo "mode preview 2" > /proc/camcap
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=60 >/dev/null 2>&1
show
echo "=== health ==="
dmesg | grep -ciE 'oops|BUG|panic|watchdog' || true
cat /proc/loadavg
