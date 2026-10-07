#!/bin/sh
# zz_shot.sh -- DEVICE SIDE. Capture one complete 12-bit full frame (4000x3000).
# usage: zz_shot.sh <tag> [dgain_hex]        defaults: tag=shot dgain=0400
# Called by scripts/zz_shot_remote.sh (WSL) which is driven by scripts/k50_shot.ps1.
IF=/proc/camcap
I2C="i2ctransfer -f -y 10"
TAG=${1:-shot}
DG=${2:-0400}

# 16-bit sensor register write: register number is 0x02xx, two data bytes
w16() { $I2C w4@0x10 0x02 $(printf '0x%02x 0x%02x 0x%02x' $1 $(( $2 >> 8 )) $(( $2 & 0xff ))) >/dev/null 2>&1; }

d=$(cat /sys/module/cam_cap/parameters/dbl_data_bus 2>/dev/null)
p=$(cat /sys/module/cam_cap/parameters/pak_mode 2>/dev/null)
b=$(cat /sys/module/cam_cap/parameters/frame_bytes 2>/dev/null)
if [ "$d" != "2" ] || [ "$p" != "130" ] || [ "$b" != "18874368" ]; then
    /sbin/rmmod cam_cap 2>/dev/null
    sleep 1
    insmod /root/cam_cap.ko dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 \
        route_pix_mode=2 frame_bytes=18874368
    echo "insmod rc=$? (dbl=$(cat /sys/module/cam_cap/parameters/dbl_data_bus) pak=$(cat /sys/module/cam_cap/parameters/pak_mode))"
else
    echo "module already: dbl=$d pak=$p frame_bytes=$b"
fi

# SENINF/CAMSV routing only has to run once per boot
if [ ! -f /tmp/.cam_routed ]; then
    echo route > $IF 2>/dev/null && touch /tmp/.cam_routed && echo "routed (once per boot)"
fi

w16 0x02 0x0380      # exposure 896 lines ~ 16 ms (integration ceiling of this mode)
w16 0x04 0x0300      # analog gain (highest effective code; 0x03c0/0x0f00 clip to this)
w16 0x0e 0x$DG       # digital gain: 0400 (recommended) / 0800 (brighter) / 1000 (clips)
sleep 1

# cfg <fmt> <pxl_start> <pxl_end> <lin_start> <lin_end> <xsize> <ysize> <stride>  (bytes!)
echo "cfg 1 0 4000 0 3000 6000 3000 6000" > $IF 2>/dev/null
echo arm > $IF 2>/dev/null
sleep 4

OUT=/tmp/$TAG.bin
dd if=$IF of=$OUT bs=1M count=19 2>/dev/null
echo "TAG=$TAG  dgain=0x$DG"
grep -E 'frame_ready|last_result|int_status' /proc/camcap_info
echo "size=$(stat -c %s $OUT)"
echo "nz=$(dd if=$OUT bs=1M 2>/dev/null | tr -d '\000' | wc -c)"
echo "md5=$(md5sum $OUT | cut -c1-32)"
echo "--- cap done ---"
