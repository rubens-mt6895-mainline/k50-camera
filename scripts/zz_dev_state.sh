#!/bin/sh
# Read-only: is the device stuck, and is cam_cap still pinned?
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null
chmod 600 "$KEY"
timeout 30 ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} '
uptime
echo "--- modules ---"
lsmod | grep -E "cam_cap|videobuf2|^video"
echo "--- camera processes ---"
ps -eo pid,ppid,stat,wchan:24,etime,comm | grep -E "v4l2-ctl|cheese|cam_cap" | grep -v grep
echo "--- uninterruptible ---"
for p in /proc/[0-9]*; do
	s=$(awk "{print \$3}" $p/stat 2>/dev/null)
	[ "$s" = "D" ] || continue
	echo "$(basename $p) $(cat $p/comm 2>/dev/null) wchan=$(cat $p/wchan 2>/dev/null)"
done
echo "--- video0 holders ---"
fuser -v /dev/video0 2>&1 | head -20
'
