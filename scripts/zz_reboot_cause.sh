#!/bin/sh
# zz_reboot_cause.sh - the head part: how the previous boot ended.
set -u

echo "=== uptime / date ==="
uptime
date

echo "=== previous boot, last 12 lines (what was running when it stopped) ==="
journalctl -b -1 -n 12 --no-pager 2>/dev/null | tail -12

echo "=== previous boot: any crash signature in its last 400 lines? ==="
journalctl -b -1 -n 400 --no-pager 2>/dev/null | grep -iE 'panic|oops|BUG:|watchdog|thermal|shutdown|reboot|oom|hung|stall' | tail -12

echo "=== previous boot: how it ended per systemd ==="
journalctl -b -1 --no-pager 2>/dev/null | grep -iE 'Reached target (Reboot|Shutdown|Power)|systemd-shutdown|Stopping|Starting Reboot|Powering off' | tail -8

echo "=== watchdog ==="
ls -l /dev/watchdog* 2>/dev/null || echo "  no /dev/watchdog*"
for w in /sys/class/watchdog/watchdog*; do
	[ -d "$w" ] || continue
	echo "  $w identity=$(cat $w/identity 2>/dev/null) timeout=$(cat $w/timeout 2>/dev/null) state=$(cat $w/state 2>/dev/null) pretimeout=$(cat $w/pretimeout 2>/dev/null)"
done

echo "=== staged v4l2 modules ==="
ls /root/v4l2/ 2>/dev/null || echo "  /root/v4l2 missing"

echo "=== boot window of the current boot ==="
journalctl -b 0 --no-pager 2>/dev/null | head -3
