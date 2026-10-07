#!/bin/sh
# zz_cap10.sh - full-frame capture with the dense PAK setting, then drain it.
rmmod cam_cap 2>/dev/null
sleep 1
dmesg -c > /dev/null 2>&1

echo "=== insmod dbl_data_bus=1 pak_dbl=0 ==="
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0
echo "insmod rc=$?"
sleep 1
head -12 /proc/camcap_info

echo "=== cfg + arm ==="
echo cfg 1 0 4000 0 3000 4000 3000 5000 > /proc/camcap
echo arm > /proc/camcap
sleep 2
head -20 /proc/camcap_info
echo "--- dmesg ---"
dmesg | grep -E "cam_cap:|iommu" | tail -12

echo "=== drain 16 MiB ==="
dd if=/proc/camcap of=/root/frame10.bin bs=1048576 count=16 2>&1 | tail -1
ls -l /root/frame10.bin
md5sum /root/frame10.bin
echo "--- first 64 bytes ---"
od -An -tx4 -N64 /root/frame10.bin
echo "--- nonzero dwords (whole 16 MiB) ---"
od -An -tx4 -v /root/frame10.bin | tr -s ' ' '\n' | grep -v '^$' | grep -vc '^00000000$'
echo "--- last 2 MiB nonzero ---"
tail -c 2097152 /root/frame10.bin > /tmp/t.bin
od -An -tx4 -v /tmp/t.bin | tr -s ' ' '\n' | grep -v '^$' | grep -vc '^00000000$'
echo "=== done ==="
