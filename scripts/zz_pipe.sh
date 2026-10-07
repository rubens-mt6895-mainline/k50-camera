#!/bin/sh
# zz_pipe.sh [threads] [frames] - two-buffer pipeline test.
#
# Checks, in order:
#   1  the improved arm poll on its own (burst 16 must be clearly above 25 fps)
#   2  a real stream with the pipeline on (period should be arm-limited, ~32 ms)
#   3  4 frames saved for a visual check
# One device task at a time; nothing runs in the background.
NTH=${1:-4}
NFR=${2:-40}
set -u

echo "=== stop any consumer ==="
pkill -x cheese 2>/dev/null
sleep 0.5
fuser -k /dev/video0 2>/dev/null
sleep 0.5

echo "=== reload (pipeline on) ==="
rmmod cam_cap 2>/dev/null
if grep -q '^cam_cap ' /proc/modules; then
	lsmod | grep cam_cap
	echo "ABORT: cam_cap is still loaded (pinned?); reboot is needed"
	exit 1
fi
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=$NTH pipeline=1
rc=$?
echo "insmod rc=$rc conv_threads=$NTH"
if [ $rc -ne 0 ]; then
	echo "ABORT: insmod failed"
	exit 1
fi
sleep 1

echo "=== buffer state ==="
grep -E 'buffer_|mapping|iommu|iova' /proc/camcap_info

echo "=== dmesg at load: second buffer must appear here ==="
dmesg | grep -E 'pipeline|cam_cap: loaded' | tail -8

dmesg -c >/dev/null 2>&1

echo "=== burst 16 (bare arm, fine-grained poll) ==="
echo route > /proc/camcap
echo "cfg 1 0 4000 0 3000 6000 3000 6000" > /proc/camcap
sleep 0.2
echo burst 16 > /proc/camcap
dmesg | grep -E 'burst'

echo "=== $NFR frames through v4l2-ctl (pipeline) ==="
timeout 240 nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$NFR \
	--stream-to=/dev/null >/tmp/pipectl.log 2>&1
echo "v4l2-ctl rc=$?"
tail -3 /tmp/pipectl.log

echo "=== /proc/camcap_info (timing + stats) ==="
grep -E 'avg|last|stats|buffer_' /proc/camcap_info

echo "=== dmesg: streaming line / pipeline events / errors ==="
dmesg | grep -E 'streaming|pipeline|pipe|failed|error|WARN|BUG' | tail -20

echo "=== 4 frames to /root/pipe.yuyv ==="
timeout 120 nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=4 \
	--stream-to=/root/pipe.yuyv >/dev/null 2>&1
ls -l /root/pipe.yuyv 2>&1

echo "=== crash scan (expect 0) ==="
dmesg | grep -cE 'Oops|paging request|BUG:'
cat /proc/loadavg
