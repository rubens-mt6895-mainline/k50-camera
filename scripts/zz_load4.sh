#!/bin/sh
# zz_load4.sh - what does the 4-thread pool do to the rest of the machine?
pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>&1
sleep 1
insmod /root/cam_cap.ko v4l2_enable=1 conv_threads=4 2>&1
echo "insmod rc=$?"
sleep 2

timeout 90 nice -n 12 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=25 --stream-to=/dev/null >/dev/null 2>&1 &
BG=$!
for i in 1 2 3 4; do
	sleep 2
	echo "--- sample $i (streaming, pid $BG) ---"
	cat /proc/loadavg
	top -bn1 2>/dev/null | sed -n '1,9p'
done
wait $BG
echo "stream done rc=$?"
echo "--- after ---"
cat /proc/loadavg
grep -E 'avg' /proc/camcap_info
dmesg | grep -c -E 'Oops|paging request'
