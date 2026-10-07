#!/bin/sh
# zz_slot.sh [frames] [mmap_buffers] - custom3 (4000x2256@60) pipeline depth sweep.
#
# Same mode and worker count; varies the number of raw frame buffers the driver
# keeps in flight (pipe_slots 3 vs 4, now with the parallel band invalidate) and
# the number of vb2 buffers the capture tool queues (--stream-mmap=N).  A period
# below the 16.67 ms sensor period means the convert path keeps up with the
# sensor.
set -u
FR=${1:-60}
MM=${2:-8}
P=/sys/module/cam_cap/parameters
R=/root

echo "=== zz_slot: custom3 4000x2256, pipe_slots 3 vs 4, mmap=$MM ==="
date

for SL in 3 4; do
	echo "=== pipe_slots=$SL, mmap=$MM ==="
	pkill -x cheese 2>/dev/null
	pkill -x guvcview 2>/dev/null
	sleep 1
	fuser -k /dev/video0 2>/dev/null
	sleep 1
	rmmod cam_cap 2>/dev/null
	sleep 1
	dmesg -c >/dev/null
	insmod $R/cam_cap.ko v4l2_enable=1 conv_threads=8 pipe_slots=$SL pipeline=1 sync_parallel=1 || {
		echo "insmod failed"
		continue
	}
	sleep 1
	echo 0 > $P/ae_enable 2>/dev/null
	echo 0 > $P/af_enable 2>/dev/null
	echo "mode custom3 1" > /proc/camcap
	sleep 0.3
	dmesg | grep -E 'cam_cap: (convert|mode|rx|pipeline)' | tail -5
	timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap=$MM --stream-count=$FR --stream-to=/dev/null 2>&1 | tail -2
	grep -E '^(avg|timing|dist)' /proc/camcap_info | head -3
done

echo "=== restoring preview on the default worker count ==="
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
timeout 30 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=30 --stream-to=/dev/null 2>&1 | tail -2
grep -E '^(avg|timing|dist)' /proc/camcap_info | head -3
echo "crashes: $(dmesg | grep -cE 'Oops|BUG:|panic|watchdog')"
echo "=== done ==="
