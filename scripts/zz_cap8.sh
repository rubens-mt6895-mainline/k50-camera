#!/bin/sh
# zz_cap8.sh - drain the 16 MiB capture buffer and look at its content.
echo "=== status ==="
head -12 /proc/camcap_info

dmesg -c > /dev/null 2>&1

echo "=== re-arm full frame ==="
echo cfg 1 0 4000 0 3000 4000 3000 5000 > /proc/camcap
echo arm > /proc/camcap
sleep 2
grep -E "arm seq|arm INT" /proc/camcap_info 2>/dev/null
dmesg | tail -6

echo "=== drain buffer ==="
dd if=/proc/camcap of=/root/frame.bin bs=1048576 count=16 2>&1 | tail -2
ls -l /root/frame.bin
md5sum /root/frame.bin

echo "=== first 128 bytes ==="
od -An -tx4 -N128 /root/frame.bin

echo "=== byte histogram (sample) ==="
od -An -tu1 -N65536 /root/frame.bin | tr -s ' ' '\n' | grep -v '^$' | sort -n | uniq -c | sort -rn | head -12

echo "=== whole-buffer stats ==="
echo -n "nonzero dwords: "
od -An -tx4 -v /root/frame.bin | tr -s ' ' '\n' | grep -v '^$' | grep -vc '^00000000$'
echo -n "total dwords  : "
od -An -tx4 -v /root/frame.bin | tr -s ' ' '\n' | grep -vc '^$'

echo "=== last 1 MiB nonzero (tail check) ==="
tail -c 1048576 /root/frame.bin > /root/frame_tail.bin
od -An -tx4 -v /root/frame_tail.bin | tr -s ' ' '\n' | grep -v '^$' | grep -vc '^00000000$'

echo "=== dmesg after ==="
dmesg | tail -10
echo "=== done ==="
