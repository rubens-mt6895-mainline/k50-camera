#!/bin/sh
# zz_kill.sh - who exactly is holding /dev/video0, can it be killed, and does
# cam_cap unload afterwards?
set -u

echo "=== fds pointing at /dev/video0 ==="
for f in /proc/[0-9]*/fd; do
	t=$(readlink -f "$f" 2>/dev/null)
	if [ "$t" = "/dev/video0" ]; then
		p=${f%/fd/*}
		echo "  $p comm=$(cat $p/comm 2>/dev/null) state=$(awk '{print $3}' $p/stat 2>/dev/null) wchan=$(cat $p/wchan 2>/dev/null)"
	fi
done
echo "=== send SIGKILL to v4l2-ctl ==="
pkill -9 -x v4l2-ctl 2>/dev/null && echo "  signal sent" || echo "  no v4l2-ctl running"
sleep 4
echo "=== survivors ==="
pgrep -ax v4l2-ctl || echo "  none"
echo "  refcnt: $(cat /sys/module/cam_cap/refcnt 2>/dev/null)"
echo "=== rmmod cam_cap ==="
rmmod cam_cap 2>&1
echo "  rc=$?"
grep '^cam_cap ' /proc/modules || echo "  [ok] cam_cap gone"
echo "=== dmesg tail ==="
dmesg | tail -6
echo "=== load ==="
cat /proc/loadavg
echo "### zz_kill done"
