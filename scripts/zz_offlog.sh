#!/bin/sh
# zz_offlog.sh - who asked for the shutdown, and any other power events today.
set -u
echo "=== boot/shutdown records today ==="
journalctl --list-boots --no-pager 2>/dev/null | tail -5
echo
echo "=== last shutdown request ==="
journalctl --since "-20h" --no-pager 2>/dev/null | grep -iE 'Requested transaction|poweroff.target|logind.*shutdown|scheduled for|System is powering down|reboot' | tail -12
echo
echo "=== 5 minutes before the previous poweroff ==="
journalctl --since "2026-10-07 08:53:00" --until "2026-10-07 08:59:00" --no-pager 2>/dev/null | head -30
echo "=== zz_offlog done ==="
