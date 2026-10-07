#!/bin/sh
# zz_diag.sh - read-only diagnosis of a stuck stream (which kernel path is
# v4l2-ctl blocked in), plus the driver's own view of the pipeline.
set -u

P=$(pgrep -x v4l2-ctl | head -1)
echo "v4l2-ctl pid=${P:-none}"
if [ -n "${P:-}" ]; then
	echo "wchan  : $(cat /proc/$P/wchan 2>/dev/null)"
	echo "syscall: $(cat /proc/$P/syscall 2>/dev/null)"
	echo "stack  :"
	cat /proc/$P/stack 2>/dev/null | head -20
fi

echo "=== cam_cap / v4l2 threads ==="
ps -e -o pid,stat,etime,comm 2>/dev/null | grep -E 'cam_cap|v4l2-ctl|COMMAND'

echo "=== module ==="
lsmod | grep cam_cap

echo "=== /proc/camcap_info ==="
head -30 /proc/camcap_info

echo "=== dmesg: cam_cap ==="
dmesg | grep -E 'cam_cap|pipeline|pipe|alloc_contig|alloc_pages_exact' | tail -30

echo "=== load ==="
cat /proc/loadavg
