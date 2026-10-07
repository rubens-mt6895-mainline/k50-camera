#!/bin/sh
# zz_c3.sh - is the custom3 frame rate limited by the driver or by the viewer?
# Runs the same 4000x2256 mode three ways: v4l2-ctl copying every frame to
# /dev/null, v4l2-ctl with more mmap buffers, and v4l2-ctl that only dequeue/
# requeues.  Prints the driver's own view after each run.
set -u
P=/sys/module/cam_cap/parameters
NF=${1:-120}
I=/proc/camcap_info
show() {
	echo "--- $1"
	grep -E '^(avg|timing|dist)' $I
}

echo "=== state ==="
cat $P/conv_threads $P/pipe_slots 2>/dev/null | tr '\n' ' '
echo
echo "af_enable=$(cat $P/af_enable 2>/dev/null)"

echo "=== custom3 4000x2256 ==="
timeout 20 v4l2-ctl -d /dev/video0 -v width=4000,height=2256 >/dev/null 2>&1
timeout 20 v4l2-ctl -d /dev/video0 --set-parm=60 >/dev/null 2>&1
dmesg | tail -3

echo
echo "=== A: --stream-mmap (default buffers) + --stream-to=/dev/null ==="
timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$NF --stream-to=/dev/null 2>&1 | tail -2
show A

echo "=== B: --stream-mmap=8 + --stream-to=/dev/null ==="
timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$NF --stream-to=/dev/null 2>&1 | tail -2
show B

echo "=== C: --stream-mmap=8, no --stream-to (no user copy) ==="
timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$NF 2>&1 | tail -2
show C

echo "=== D: --stream-mmap=12, no --stream-to ==="
timeout 60 v4l2-ctl -d /dev/video0 --stream-mmap=12 --stream-count=$NF 2>&1 | tail -2
show D

echo "=== health ==="
dmesg | grep -ciE 'oops|BUG|panic|watchdog' || true
cat /proc/loadavg
