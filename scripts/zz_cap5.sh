#!/bin/sh
# IOMMU-backed capture attempt.  Serial, low priority, single device task.
G=/root/gpiotoolG
echo "=== 0. env ==="
date; uptime; nproc
echo "--- sensor still streaming? ---"
echo "PKT=$(busybox devmem 0x1a014adc 32) IRQ=$(busybox devmem 0x1a014ac8 32)"
echo "0100=$(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1)"

echo "=== 1. unload old cam_cap ==="
rmmod cam_cap 2>&1
sleep 1
grep cam_cap /proc/modules || echo "(cam_cap gone)"

echo "=== 2. dmesg baseline ==="
dmesg -c > /root/dmesg_pre.txt 2>/dev/null
wc -l /root/dmesg_pre.txt

echo "=== 3. insmod with IOMMU path ==="
nice -n 19 timeout 90 insmod /root/cam_cap.ko dbl_data_bus=1
echo "insmod rc=$?"
sleep 1
grep cam_cap /proc/modules || echo "(cam_cap NOT loaded)"

echo "=== 4. dmesg after insmod ==="
dmesg | tail -60

echo "=== 5. info ==="
cat /proc/camcap_info

echo "=== 6. route + arm ==="
echo cfg 1 0 4000 0 3000 4000 3000 5000 > /proc/camcap
echo route > /proc/camcap
echo arm > /proc/camcap
sleep 1

echo "=== 7. info after arm ==="
cat /proc/camcap_info

echo "=== 8. dmesg after arm ==="
dmesg | tail -40

echo "=== 9. buffer nonzero words (first 64 KiB) ==="
dd if=/proc/camcap bs=4096 count=16 2>/dev/null | od -An -tx4 | tr -s ' ' '\n' | grep -v '^$' | grep -vc '^00000000$'

echo "=== 10. first 8 nonzero dwords ==="
dd if=/proc/camcap bs=4096 count=16 2>/dev/null | od -An -tx4 | tr -s ' ' '\n' | grep -v '^$' | grep -v '^00000000$' | head -8

echo "=== 11. IOMMU / larb / dts ==="
echo "PT_BASE=$(busybox devmem 0x1e802000 32)"
echo "larb0_p2=$(busybox devmem 0x14021388 32)"
ls -d /proc/device-tree/soc*/camcap* 2>&1
cat "/proc/device-tree/soc@0/camcap@1a110000/iommus" 2>/dev/null | od -An -tx1
dmesg | grep -iE "XAGA|iommu|fault" | tail -30
echo "=== done ==="
