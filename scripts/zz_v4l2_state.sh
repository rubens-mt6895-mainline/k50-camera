#!/bin/sh
# zz_v4l2_state.sh - read-only state check before loading the V4L2-enabled cam_cap.ko
echo "=== uptime / memory ==="
cat /proc/uptime
grep -E '^MemFree|^CmaFree|^MemAvailable' /proc/meminfo
echo "=== modules of interest ==="
grep -E '^(cam_cap|mc|videodev|videobuf2-[a-z]+) ' /proc/modules
echo "=== video4linux in /proc/devices ==="
grep -i 'video' /proc/devices || echo "(no video major)"
echo "=== /dev/video* ==="
ls -l /dev/video* 2>/dev/null || echo "(none)"
echo "=== cam_cap parameters ==="
for p in dbl_data_bus pak_mode pak_dbl route_pix_mode frame_bytes single_mode v4l2_enable out_width out_height; do
	printf '%s = %s\n' "$p" "$(cat /sys/module/cam_cap/parameters/$p 2>&1)"
done
echo "=== IMX582 streaming? (0x0100) ==="
i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1@0x10 2>&1 || echo "(i2c read failed)"
echo "=== doorbells ==="
printf 'SENINF_TOP_MUX_CTRL=%s\n' "$(busybox devmem 0x1a011d00 32 2>&1)"
printf 'CSI2_PACKET_CNT   =%s\n' "$(busybox devmem 0x1a014adc 32 2>&1)"
printf 'TG_VF_CON         =%s\n' "$(busybox devmem 0x1a110104 32 2>&1)"
printf 'cam_mux3_ctrl     =%s\n' "$(busybox devmem 0x1a010460 32 2>&1)"
echo "=== camcap_info (head) ==="
head -14 /proc/camcap_info 2>&1
echo "=== root ==="
ls -l /root/cam_cap.ko /root/mc.ko /root/videodev.ko /root/videobuf2-*.ko 2>&1 | head -12
echo "=== v4l-utils / camera apps ==="
for t in v4l2-ctl cheese kamoso snapshot gnome-snapshot guvcview ffmpeg gst-launch-1.0; do
	printf '%-16s %s\n' "$t" "$(command -v $t 2>/dev/null || echo -)"
done
echo "=== done ==="
