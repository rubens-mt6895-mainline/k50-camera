#!/bin/sh
# zz_cap7.sh - load the fixed-IOVA cam_cap.ko and inspect the buffer setup.
echo "=== unload old module ==="
rmmod cam_cap 2>&1
sleep 1
if grep -q cam_cap /proc/modules; then echo "STILL LOADED"; else echo "cam_cap gone"; fi
dmesg -c > /dev/null 2>&1

echo "=== insmod new (dbl_data_bus=1, map_iova default) ==="
insmod /root/cam_cap.ko dbl_data_bus=1
echo "insmod rc=$?"
sleep 1
head -22 /proc/camcap_info
echo "--- dmesg ---"
dmesg | tail -25

echo "=== IOMMU side ==="
echo -n "PT_BASE 0x1e802000 = "
busybox devmem 0x1e802000 32
echo -n "DT node iommus   = "
od -An -tx1 /proc/device-tree/soc@0/camcap@1a110000/iommus 2>/dev/null

echo "=== full frame arm ==="
dmesg -c > /dev/null 2>&1
echo cfg 1 0 4000 0 3000 4000 3000 5000 > /proc/camcap
echo arm > /proc/camcap
sleep 2
head -22 /proc/camcap_info
echo "--- new dmesg ---"
dmesg | tail -20
echo "=== done ==="
