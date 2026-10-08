#!/bin/bash
# Mount the extracted erofs partitions read-only (needs root).
set -e
P=${K50_REPO}/out/re/parts
for n in vendor_a odm_a vendor_dlkm_a; do
    m=/mnt/rom/$n
    mkdir -p $m
    if mountpoint -q $m; then echo "$m already mounted"; else
        mount -t erofs -o loop,ro $P/$n.img $m && echo "mounted $n -> $m"
    fi
done
echo '=== /mnt/rom/vendor_a/lib64 camera 3a files ==='
ls -l /mnt/rom/vendor_a/lib64/ | grep -iE 'lib3a\.|libcam\.(afmgr|hal3a\.(lensdrv|oisdrv|afassitmgr))' | head -20
echo '=== /mnt/rom/vendor_a/etc/camera ==='
ls -l /mnt/rom/vendor_a/etc/camera/ | head -20
echo '=== xiaomi subdir ==='
ls -l /mnt/rom/vendor_a/etc/camera/xiaomi/ 2>/dev/null | head -30
echo '=== vendor_dlkm modules of interest ==='
ls -l /mnt/rom/vendor_dlkm_a/lib/modules/ 2>/dev/null | grep -iE 'dw98|ak73|bu64|camera_af|af_|ois|eeprom' | head -20
