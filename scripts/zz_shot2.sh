#!/bin/sh
# zz_shot2.sh - get a picture of the phone screen showing the camera app.
# 1) try the xdg-desktop-portal Screenshot request again, watching all session
#    signals, 2) if that yields nothing, restart cheese on the X11 backend and
#    grab the Xwayland root window with ImageMagick.
export DEBIAN_FRONTEND=noninteractive
U=k50
RT=/run/user/1000
run() {
	runuser -u $U -- env XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 \
		DISPLAY=:0 XAUTHORITY=$RT/xauth_yypUzY DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus "$@"
}

echo "=== (1) portal screenshot attempt ==="
rm -f /tmp/sig.log /tmp/portal_shot.png
run dbus-monitor --session "type='signal'" >/tmp/sig.log 2>&1 &
MON=$!
sleep 2
run gdbus call --session --dest org.freedesktop.portal.Desktop \
	--object-path /org/freedesktop/portal/desktop \
	--method org.freedesktop.portal.Screenshot.Screenshot \
	"" "{'interactive': <false>}" 2>&1
sleep 8
kill $MON 2>/dev/null
grep -A6 -iE 'Response|Screenshot|uri' /tmp/sig.log 2>&1 | head -40
echo "--- png candidates ---"
find /tmp /run/user/1000 -maxdepth 2 -name '*.png' -newermt '-3 minutes' 2>/dev/null | head

echo "=== (2) imagemagick + cheese on the X11 backend ==="
which import >/dev/null 2>&1 || nice -n 19 apt-get install -y --no-install-recommends imagemagick 2>&1 \
	| grep -viE 'mandb|^$' | tail -3

pkill -f '/usr/bin/cheese' 2>/dev/null
sleep 2
run env GDK_BACKEND=x11 setsid cheese >/tmp/cheese_x11.log 2>&1 </dev/null &
sleep 18
echo "--- cheese ---"
pgrep -a cheese 2>&1
tail -15 /tmp/cheese_x11.log 2>&1
echo "--- import root window ---"
run import -window root /tmp/shot.png 2>&1 | tail -3
ls -l /tmp/shot.png 2>&1
echo "--- camcap ---"
grep -E 'frame_ready|arm_count|last_seq|vf_on' /proc/camcap_info 2>&1
echo "=== done ==="
