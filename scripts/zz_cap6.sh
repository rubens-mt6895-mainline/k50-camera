#!/bin/sh
# Partial-frame capture: 4000 x 200 lines = 1,000,000 B, fits the 1 MiB buffer.
echo "=== info before ==="
head -6 /proc/camcap_info

dmesg -c > /dev/null 2>&1

echo "=== cfg (grab 0..200 lines, out 4000x200, stride 5000) + arm ==="
echo stop > /proc/camcap
echo cfg 1 0 4000 0 200 4000 200 5000 > /proc/camcap
echo arm > /proc/camcap
sleep 1
head -16 /proc/camcap_info
echo "--- new dmesg ---"
dmesg | tail -8

echo "=== save frame A ==="
dd if=/proc/camcap of=/root/frameA.bin bs=4096 count=256 2>/dev/null
ls -l /root/frameA.bin
md5sum /root/frameA.bin
echo "--- first 64 bytes ---"
od -An -tx4 -N64 /root/frameA.bin
echo "--- nonzero dwords in frame A ---"
od -An -tx4 -v /root/frameA.bin | tr -s ' ' '\n' | grep -v '^$' | grep -vc '^00000000$'

echo "=== arm again, save frame B ==="
echo arm > /proc/camcap
sleep 1
dd if=/proc/camcap of=/root/frameB.bin bs=4096 count=256 2>/dev/null
md5sum /root/frameB.bin
cmp /root/frameA.bin /root/frameB.bin > /dev/null && echo "IDENTICAL" || echo "DIFFERENT"
echo "=== done ==="
