#!/bin/sh
# zz_iommu_probe.sh - find out which devices are behind the camera IOMMU.
echo "=== top-level device tree ==="
ls /proc/device-tree | head -20
echo "=== nodes named *camsv* / *cam* ==="
ls -d /proc/device-tree/*camsv* 2>/dev/null
ls -d /proc/device-tree/soc*camsv* /proc/device-tree/soc*/*camsv* 2>/dev/null
echo "=== iommu nodes ==="
ls -d /proc/device-tree/*iommu* /proc/device-tree/soc*iommu* /proc/device-tree/soc*/*iommu* 2>/dev/null
echo "=== find all iommus properties (first 60) ==="
find /proc/device-tree -name iommus -print 2>/dev/null | head -60
echo "=== count ==="
find /proc/device-tree -name iommus -print 2>/dev/null | wc -l
echo "=== platform devices with cam/smi/larb/iommu in the name ==="
ls /sys/bus/platform/devices/ 2>/dev/null | grep -iE 'cam|smi|larb|iommu|seninf' | head -60
echo "=== 1e802000 / 1e810000 iommu sysfs ==="
ls -d /sys/devices/platform/soc*/*iommu* 2>/dev/null
for d in /sys/devices/platform/*iommu*; do
	[ -d "$d" ] || continue
	echo "--- $d"
	ls "$d" 2>/dev/null | head -30
	echo "    driver: $(readlink -f $d/driver 2>/dev/null)"
done
echo "=== does any DT node reference the iommu phandle? show first 8 raw ==="
for f in $(find /proc/device-tree -name iommus -print 2>/dev/null | head -8); do
	echo "--- $f"
	od -A x -t x4 "$f" 2>/dev/null | head -3
done
echo "=== cam_cap module still loaded? ==="
grep cam_cap /proc/modules
echo "=== dmesg: iommu probe lines ==="
dmesg | grep -iE 'iommu|smi' | head -40
echo "=== zz_iommu_probe done ==="
