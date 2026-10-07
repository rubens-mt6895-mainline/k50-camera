#!/bin/sh
# zz_cheese_check.sh - launch Cheese the way the user does and prove it really streams.
# Liveness is judged ONLY by arm_count growth (a fake-alive Cheese keeps its fds
# but stops queueing buffers).
UI=k50
U=/run/user/1000

echo "=== 0. before ==="
grep -E 'arm_count|last_seq|frame_ready' /proc/camcap_info
grep -E 'convert :|timing :|avg' /proc/camcap_info

echo
echo "=== 1. stop stale instances ==="
pkill -x cheese 2>/dev/null; sleep 1
fuser -k /dev/video0 2>/dev/null; sleep 1
echo "  holders now: $(fuser /dev/video0 2>&1)"

echo
echo "=== 2. start cheese as $UI ==="
runuser -u "$UI" -- env \
	XDG_RUNTIME_DIR=$U \
	WAYLAND_DISPLAY=wayland-0 \
	DISPLAY=:0 \
	DBUS_SESSION_BUS_ADDRESS=unix:path=$U/bus \
	nohup setsid cheese >/tmp/cheese.log 2>&1 </dev/null &
sleep 8

echo "=== 3. streaming? (arm_count must keep growing) ==="
i=0
while [ $i -lt 8 ]; do
	printf "  t=%2ds  %s\n" $((8 + i * 3)) "$(grep -E 'arm_count|last_seq' /proc/camcap_info | tr '\n' ' ')"
	i=$((i + 1))
	[ $i -lt 8 ] && sleep 3
done

echo
echo "=== 4. driver timing while cheese runs ==="
grep -E 'convert :|timing :|avg' /proc/camcap_info

echo
echo "=== 5. process / log ==="
pgrep -a cheese 2>/dev/null || echo "  cheese not running"
echo "  --- /tmp/cheese.log (tail 6) ---"
tail -6 /tmp/cheese.log 2>/dev/null | sed 's/^/    /'

echo
echo "=== 6. load / temperature ==="
uptime
cat /proc/loadavg

echo
echo "=== 7. recent dmesg ==="
dmesg | tail -4
