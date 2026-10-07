#!/bin/sh
# zz_rates.sh - the confirmed 60/120 modes after the converter work.
#
# conv_threads=8, pipe_slots=4, sync_parallel=1; every mode is streamed with 8
# vb2 buffers so buffer starvation cannot cap the rate.  The last line of each
# block is the steady state (timing) and the 100+ frame average (avg).
set -u
P=/sys/module/cam_cap/parameters
R=/root
FR=${1:-150}

echo "=== zz_rates: native capture rates, conv_threads=8 pipe_slots=4 sync_parallel=1 ==="
date

pkill -x cheese 2>/dev/null
pkill -x guvcview 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>/dev/null
sleep 1
dmesg -c >/dev/null
insmod $R/cam_cap.ko v4l2_enable=1 conv_threads=8 pipe_slots=4 pipeline=1 sync_parallel=1 || exit 1
sleep 1
echo 0 > $P/ae_enable 2>/dev/null
echo 0 > $P/af_enable 2>/dev/null
dmesg | grep -E 'cam_cap: (convert|source|output|pipeline|v4l2)' | tail -8

run() {
	echo "--- $1 ($2 frames, mmap=8) ---"
	echo "$3" > /proc/camcap
	sleep 0.4
	dmesg | grep -E 'cam_cap: (mode|rx)' | tail -2
	timeout 120 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$2 --stream-to=/dev/null 2>&1 | tail -1
	grep -E '^(avg|timing|dist|stats)' /proc/camcap_info | head -4
}

run "normal_video 4000x2256@30 (native)" $FR "mode normal_video 1"
run "custom3 4000x2256@60 (native)" $FR "mode custom3 1"
run "custom2 1920x1080@120 (native)" $FR "mode custom2 1"
run "preview binned 2000x1500@33" 100 "mode preview 2"

echo "=== restoring preview ==="
pkill -x v4l2-ctl 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>/dev/null
dmesg -c >/dev/null
insmod $R/cam_cap.ko v4l2_enable=1 conv_threads=8 pipeline=1
sleep 1
python3 $R/csirx_bring.py 2 685 1 4 68 2>&1 | tail -3
echo "mode preview 2" > /proc/camcap
sleep 0.3
timeout 30 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=30 --stream-to=/dev/null 2>&1 | tail -1
grep -E '^(avg|timing|dist)' /proc/camcap_info | head -3
echo "crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog')"
echo "=== done ==="
