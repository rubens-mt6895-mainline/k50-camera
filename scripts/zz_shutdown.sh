#!/bin/sh
# zz_shutdown.sh - what (if anything) is scheduled to power this device off.
set -u
date
echo "=== systemd timers ==="
systemctl list-timers --all --no-pager 2>/dev/null | head -14
echo "=== units matching shut/power/off ==="
ls -1 /etc/systemd/system/ | grep -iE 'shut|power|off' || echo "(none)"
echo "=== cron ==="
crontab -l 2>/dev/null || echo "(no root crontab)"
grep -vE '^#|^$' /etc/crontab 2>/dev/null || true
ls -1 /etc/cron.d 2>/dev/null | while read f; do echo "-- $f"; grep -vE '^#|^$' "/etc/cron.d/$f"; done
echo "=== at jobs ==="
atq 2>/dev/null || echo "(no atq)"
echo "=== rtc wakealarm ==="
for f in /sys/class/rtc/rtc*/wakealarm; do
	[ -f "$f" ] || continue
	echo "$f = $(cat "$f")"
done
echo "=== last power events (journal) ==="
journalctl --since "-14h" --no-pager 2>/dev/null | grep -iE 'poweroff|shutdown scheduled|System is powering down|Shutting down' | tail -5
echo "=== zz_shutdown done ==="
