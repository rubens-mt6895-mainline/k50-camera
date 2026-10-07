#!/bin/sh
# zz_stuck.sh - read-only: where is the stuck streamer waiting, and are the
# cam_cap kthreads still spinning?
set -u

echo "=== processes ==="
ps -eo pid,stat,wchan:24,etime,args | grep -E 'v4l2-ctl|cheese|cam_cap' | grep -v grep
echo "=== cam_cap kernel threads ==="
ps -eLo pid,tid,stat,wchan:24,comm 2>/dev/null | grep cam_cap
echo "=== refcnt ==="
cat /sys/module/cam_cap/refcnt 2>/dev/null
for p in $(pgrep -x v4l2-ctl 2>/dev/null); do
	echo "=== pid $p ==="
	echo "  state: $(awk '{print $3}' /proc/$p/stat 2>/dev/null) wchan: $(cat /proc/$p/wchan 2>/dev/null)"
	echo "  fds:"
	ls -l /proc/$p/fd 2>/dev/null | grep -E 'video|dri|dma' | sed 's/^/    /'
	echo "  kernel stack:"
	cat /proc/$p/stack 2>/dev/null | sed 's/^/    /'
	echo "  syscall: $(cat /proc/$p/syscall 2>/dev/null)"
done
echo "=== dmesg tail ==="
dmesg | tail -8
echo "=== camcap info head ==="
head -14 /proc/camcap_info 2>/dev/null
echo "=== load ==="
cat /proc/loadavg
echo "### zz_stuck done"
