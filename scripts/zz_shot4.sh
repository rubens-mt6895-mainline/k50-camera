#!/bin/sh
# zz_shot4.sh - k50's Xwayland is :1 (see Xwayland -auth ...), so force the
# X11 backend onto :1 and grab the root window there.
U=k50
RT=/run/user/1000
DISP=:1
XAUTH=$RT/xauth_yypUzY

run() {
	runuser -u $U -- env XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 \
		DISPLAY=$DISP XAUTHORITY=$XAUTH DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus "$@"
}

echo "=== probe :1 ==="
run import -display :1 -window root /tmp/probe1.png 2>&1 | tail -2
ls -l /tmp/probe1.png 2>&1

echo "=== relaunch cheese on the X11 backend (:1) ==="
pkill -x cheese 2>/dev/null
sleep 2
run env GDK_BACKEND=x11 setsid cheese >/tmp/cheese_x11.log 2>&1 </dev/null &
sleep 22
pgrep -a cheese 2>&1
tail -12 /tmp/cheese_x11.log 2>&1

echo "=== grab root window on :1 ==="
run import -display :1 -window root /tmp/shot.png 2>&1 | tail -2
ls -l /tmp/shot.png 2>&1

echo "=== camcap ==="
grep -E 'frame_ready|arm_count|last_seq|vf_on' /proc/camcap_info 2>&1
echo "=== done ==="
