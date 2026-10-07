#!/bin/sh
# zz_single.sh - reload cam_cap.ko with single_mode=1 and prove the frame buffer
# is frozen (no tearing) by hashing it minutes apart.
#
# With VFDATA_EN alone the TG free-runs: arm() polls INT_STATUS every 5 ms while
# a frame takes ~65 ms, so a second frame can start and overwrite the head of the
# buffer before vf_off().  SINGLE_MODE moves the stop into the hardware.
M=/sys/module/cam_cap/parameters

echo "=== unload/reload with single_mode=1"
rmmod cam_cap || { echo "rmmod failed"; exit 1; }
insmod /root/cam_cap.ko dbl_data_bus=2 pak_mode=0x82 pak_dbl=2 route_pix_mode=2 \
	frame_bytes=18874368 single_mode=1 || { echo "insmod failed"; exit 1; }
for p in dbl_data_bus pak_mode pak_dbl route_pix_mode frame_bytes single_mode; do
	printf '   %s=' "$p"; cat "$M/$p"
done

echo "=== cfg + arm (single shot)"
echo "cfg 1 0 4000 0 3000 6000 3000 6000" > /proc/camcap
nice -n 19 sh -c 'echo arm > /proc/camcap'
grep -E 'frame_ready|last_result|last_int_st|arm_count|last_seq' /proc/camcap_info | sed 's/^/   /'

echo "=== VF state right after arm (must be off/low):"
busybox devmem 0x1a110104

echo "=== buffer hashes over time (identical => no tearing)"
for t in 1 3 6; do
	sleep "$t"
	h=$(dd if=/proc/camcap bs=1M count=18 2>/dev/null | md5sum | cut -d' ' -f1)
	echo "   t+$t s: $h"
done

echo "=== non-zero byte count:"
dd if=/proc/camcap bs=1M count=18 2>/dev/null | tr -d '\000' | wc -c
echo "=== VFDATA_EN now:"
busybox devmem 0x1a110104
echo "=== done"
