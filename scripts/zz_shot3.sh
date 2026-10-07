#!/bin/sh
# zz_shot3.sh - find the desktop session's real DISPLAY/XAUTHORITY, restart
# cheese on the X11 backend there, and grab the X root window.
U=k50
RT=/run/user/1000

echo "=== Xwayland processes ==="
ps -eo pid,user,args 2>/dev/null | grep -E 'Xwayland' | grep -v grep

PID=$(pgrep -x cheese | head -1)
echo "=== cheese pid=$PID env ==="
if [ -n "$PID" ]; then
	tr '\0' '\n' < /proc/$PID/environ 2>/dev/null \
		| grep -E '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|XDG_RUNTIME_DIR|XDG_SESSION_TYPE|GDK_BACKEND)='
fi

DISP=$(tr '\0' '\n' < /proc/$PID/environ 2>/dev/null | sed -n 's/^DISPLAY=//p')
XAUTH=$(tr '\0' '\n' < /proc/$PID/environ 2>/dev/null | sed -n 's/^XAUTHORITY=//p')
[ -n "$DISP" ] || DISP=:1
[ -n "$XAUTH" ] || XAUTH=$RT/xauth_yypUzY
echo "using DISPLAY=$DISP XAUTHORITY=$XAUTH"

run() {
	runuser -u $U -- env XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 \
		DISPLAY=$DISP XAUTHORITY=$XAUTH DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus "$@"
}

echo "=== xdpyinfo-ish probe ==="
run xdpyinfo 2>&1 | head -4

echo "=== restart cheese on X11 ==="
pkill -x cheese 2>/dev/null
sleep 2
run env GDK_BACKEND=x11 setsid cheese >/tmp/cheese_x11.log 2>&1 </dev/null &
sleep 20
pgrep -a cheese 2>&1
tail -12 /tmp/cheese_x11.log 2>&1

echo "=== grab root window ==="
run import -window root /tmp/shot.png 2>&1 | tail -2
ls -l /tmp/shot.png 2>&1

echo "=== camcap ==="
grep -E 'frame_ready|arm_count|last_seq|vf_on' /proc/camcap_info 2>&1
echo "=== done ==="
