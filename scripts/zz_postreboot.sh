#!/bin/sh
# zz_postreboot.sh - what survived the reboot: watchdog, module staging, helpers.
set -u

echo "=== uptime / date ==="
uptime
date

echo "=== watchdog ==="
ls -l /dev/watchdog* 2>/dev/null
for w in /sys/class/watchdog/watchdog*; do
	[ -d "$w" ] || continue
	echo "$w: identity=$(cat $w/identity 2>/dev/null) timeout=$(cat $w/timeout 2>/dev/null) state=$(cat $w/state 2>/dev/null)"
done
dmesg | grep -iE 'watchdog|wdt' | head -5

echo "=== why did we come back? (previous boot's last lines) ==="
journalctl -b -1 -n 6 --no-pager 2>/dev/null | tail -6

echo "=== staged modules ==="
ls -l /root/v4l2/ 2>/dev/null | head -12
ls -l /root/cam_cap.ko 2>/dev/null

echo "=== /root helper scripts ==="
ls -l /root/*.sh 2>/dev/null | head -30

echo "=== systemd units mentioning camera/v4l2 ==="
grep -rl -iE 'cam_cap|v4l2|cheese' /etc/systemd/system/ 2>/dev/null | head -10
systemctl list-units --type=service --state=running 2>/dev/null | head -20

echo "=== i2c adapters (sensor bus) ==="
for d in /sys/bus/i2c/devices/i2c-*; do
	printf '%s %s\n' "$(basename $d)" "$(cat $d/name 2>/dev/null)"
done

echo "=== who else is on the box ==="
ps -eo pid,user,etime,pcpu,comm --sort=-pcpu 2>/dev/null | head -12
cat /proc/loadavg
