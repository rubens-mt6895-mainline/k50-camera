#!/bin/sh
# zz_armdiag2.sh - CMA headroom (can we afford a second frame buffer?) and
# conv_threads=8 with the now-cacheable raw reads.
set -u

echo "=== CMA headroom ==="
grep -E 'CmaTotal|CmaFree|MemFree|MemAvailable' /proc/meminfo
for d in /sys/kernel/debug/cma/*; do
	[ -d "$d" ] || continue
	echo "--- $d"
	head -c 200 "$d/count" 2>/dev/null; echo
	head -c 200 "$d/alloc" 2>/dev/null; echo
done

echo "=== conv_threads=8 stream (20 frames) ==="
pkill -x cheese 2>/dev/null
sleep 0.3
fuser -k /dev/video0 2>/dev/null
sleep 0.3
rmmod cam_cap 2>/dev/null
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=8
sleep 0.5

nice -n 19 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=20 \
	--stream-to=/dev/null 2>&1 | tail -3

echo "=== info ==="
grep -E 'avg |stats :|convert |timing |frames=' /proc/camcap_info

echo "=== dmesg tail ==="
dmesg | tail -6

echo "=== crash scan (expect 0) ==="
dmesg | grep -cE 'Oops|paging request|BUG:'
cat /proc/loadavg
