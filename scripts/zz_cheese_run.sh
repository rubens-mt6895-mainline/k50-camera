#!/bin/sh
# zz_cheese_run.sh - launch the GNOME camera app (cheese) inside the k50 KDE
# Wayland session, then check that it really opened /dev/video0, and grab a
# screenshot of the screen so the preview can be inspected off-device.
export DEBIAN_FRONTEND=noninteractive
U=k50
RT=/run/user/1000

echo "=== session sockets ==="
ls $RT/ 2>&1 | tr '\n' ' '
echo
ls -l /tmp/.X11-unix/ 2>&1

echo "=== install spectacle (screenshot, best effort) ==="
nice -n 19 apt-get install -y --no-install-recommends spectacle 2>&1 \
	| grep -viE 'mandb|^$' | tail -3

echo "=== launch cheese as $U ==="
pkill -f '/usr/bin/cheese' 2>/dev/null
sleep 1
runuser -u $U -- env XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
	DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus \
	setsid cheese >/tmp/cheese.log 2>&1 </dev/null &
sleep 15

echo "--- cheese processes ---"
pgrep -a cheese 2>&1

echo "--- cheese log (tail) ---"
tail -30 /tmp/cheese.log 2>&1

echo "--- dmesg (tail) ---"
dmesg | tail -8

echo "--- camcap counters ---"
grep -E 'frame_ready|arm_count|last_seq|vf_on' /proc/camcap_info 2>&1

echo "--- screenshot via spectacle ---"
runuser -u $U -- env XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
	DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus \
	spectacle -b -n -o /tmp/shot.png 2>&1 | tail -3
sleep 5
ls -l /tmp/shot.png 2>&1
echo "=== done ==="
