#!/bin/sh
# zz_cheese_restart.sh - leave the GNOME camera app running on the phone's own
# Wayland session (native backend), and report proof that it is streaming.
U=k50
RT=/run/user/1000
XAUTH=$RT/xauth_yypUzY

run() {
	runuser -u $U -- env XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 \
		DISPLAY=:1 XAUTHORITY=$XAUTH DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus "$@"
}

echo "=== before ==="
ls -l /home/k50/.gnome2/cheese/media/ 2>&1 | tail -4
grep -E 'arm_count|last_seq' /proc/camcap_info 2>&1

pkill -x cheese 2>/dev/null
sleep 2
echo "=== start cheese (native wayland) ==="
run setsid cheese >/tmp/cheese.log 2>&1 </dev/null &
sleep 25

echo "=== process ==="
pgrep -a cheese 2>&1
echo "=== log ==="
tail -8 /tmp/cheese.log 2>&1
echo "=== camcap ==="
grep -E 'frame_ready|arm_count|last_seq|vf_on' /proc/camcap_info 2>&1
echo "=== new media ==="
ls -l /home/k50/.gnome2/cheese/media/ 2>&1 | tail -4
echo "=== disk ==="
df -h /home 2>&1 | tail -1
echo "=== done ==="
