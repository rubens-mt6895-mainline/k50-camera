#!/bin/sh
# zz_settle_shot.sh - long-ish pool run, then capture a settled frame.
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>&1
sleep 1
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=4 2>&1
echo "insmod rc=$?"
sleep 2

echo "=== 60 frames to /dev/null (AE/AWB auto) ==="
timeout 120 nice -n 12 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=60 --stream-to=/dev/null >/dev/null 2>&1 &
BG=$!
for i in 1 2 3; do
	sleep 4
	echo -n "  load[$i]: "; cat /proc/loadavg
done
wait $BG
echo "  stream rc=$?"
grep -E 'convert|avg|stats|ae |awb ' /proc/camcap_info

echo "=== capture one settled frame ==="
rm -f /root/settled.yuyv
nice -n 12 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=/root/settled.yuyv >/dev/null 2>&1
echo "  settled.yuyv: $(stat -c %s /root/settled.yuyv 2>/dev/null) bytes"
grep -E 'stats|ae |awb ' /proc/camcap_info
echo -n "  crash lines: "
dmesg | grep -c -E 'Oops|paging request'
uptime
