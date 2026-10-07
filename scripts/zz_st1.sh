#!/bin/sh
# zz_st1.sh - one-shot device state check before the single_mode test.
M=/sys/module/cam_cap/parameters
echo "== uptime: $(cat /proc/uptime)"
echo "== cam_cap params:"
for p in dbl_data_bus pak_mode pak_dbl route_pix_mode frame_bytes single_mode iommu_dev map_iova; do
	printf '   %s=' "$p"; cat "$M/$p" 2>/dev/null
done
echo "== modules (count $(wc -l < /proc/modules)):"
grep -E '^(mc|videodev|videobuf2|cam_cap) ' /proc/modules | awk '{print "   "$1" "$3" "$5}'
echo "== /proc/devices:"
grep -E 'video' /proc/devices | sed 's/^/   /'
echo "== /proc/camcap_info:"
head -25 /proc/camcap_info 2>/dev/null | sed 's/^/   /'
echo "== IMX582 0x0100 (stream on?):"
i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r2@0x10
echo "== CSI2_PACKET_CNT 0x1a014adc:"
busybox devmem 0x1a014adc
echo "== free mem:"
grep -E 'MemFree|CmaFree' /proc/meminfo | sed 's/^/   /'
