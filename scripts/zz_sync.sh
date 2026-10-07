#!/bin/sh
# zz_sync.sh [frames] - custom3 (4000x2256@60) with sync_parallel=1 vs 0.
#
# Same mode, same worker count (8) and same pipeline depth (3 slots); only the
# raw-buffer cache maintenance changes: each worker invalidating its own row
# band (1) versus one full-frame invalidate on the converter thread before the
# workers start (0).  The `sync=` field of /proc/camcap_info reports both.
set -u
FR=${1:-60}
P=/sys/module/cam_cap/parameters
R=/root

echo "=== zz_sync: custom3 4000x2256, sync_parallel 1 vs 0 (conv_threads=8, pipe_slots=3) ==="
date

for SY in 1 0; do
	echo "=== sync_parallel=$SY ==="
	pkill -x cheese 2>/dev/null
	pkill -x guvcview 2>/dev/null
	sleep 1
	fuser -k /dev/video0 2>/dev/null
	sleep 1
	rmmod cam_cap 2>/dev/null
	sleep 1
	dmesg -c >/dev/null
	insmod $R/cam_cap.ko v4l2_enable=1 conv_threads=8 pipe_slots=3 pipeline=1 sync_parallel=$SY || {
		echo "insmod failed"
		continue
	}
	sleep 1
	echo 0 > $P/ae_enable 2>/dev/null
	echo 0 > $P/af_enable 2>/dev/null
	echo "mode custom3 1" > /proc/camcap
	sleep 0.3
	dmesg | grep -E 'cam_cap: (convert|mode|rx|source|output|pipeline)' | tail -6
	timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$FR --stream-to=/dev/null 2>&1 | tail -2
	grep -E '^(avg|timing|dist|stats)' /proc/camcap_info | head -4
done

echo "=== restoring preview on the default worker count ==="
pkill -x v4l2-ctl 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>/dev/null
dmesg -c >/dev/null
insmod $R/cam_cap.ko v4l2_enable=1 conv_threads=8 pipeline=1
sleep 1
python3 $R/csirx_bring.py 2 685 1 4 68 2>&1 | tail -4
echo "mode preview 2" > /proc/camcap
sleep 0.3
timeout 30 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=30 --stream-to=/dev/null 2>&1 | tail -2
grep -E '^(avg|timing|dist)' /proc/camcap_info | head -3
echo "crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog')"
echo "=== done ==="
