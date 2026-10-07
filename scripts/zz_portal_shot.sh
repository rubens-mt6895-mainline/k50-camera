#!/bin/sh
# zz_portal_shot.sh - ask the xdg-desktop-portal (kwin backend) for a screenshot
# of the running KDE Wayland session, then copy it somewhere we can read.
RT=/run/user/1000
U=k50
run() {
	runuser -u $U -- env XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 \
		DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus "$@"
}

echo "=== portal Screenshot version ==="
run gdbus call --session --dest org.freedesktop.portal.Desktop \
	--object-path /org/freedesktop/portal/desktop \
	--method org.freedesktop.DBus.Properties.Get \
	org.freedesktop.portal.Screenshot version 2>&1

rm -f /tmp/portal.log
run gdbus monitor --session --dest org.freedesktop.portal.Desktop >/tmp/portal.log 2>&1 &
MON=$!
sleep 2

echo "=== Screenshot() call ==="
run gdbus call --session --dest org.freedesktop.portal.Desktop \
	--object-path /org/freedesktop/portal/desktop \
	--method org.freedesktop.portal.Screenshot.Screenshot \
	"" "{'interactive': <false>}" 2>&1
sleep 6
kill $MON 2>/dev/null

echo "=== monitor log ==="
cat /tmp/portal.log 2>&1

echo "=== candidate files ==="
ls -lt /tmp/*.png $RT/doc/* 2>&1 | head -10
echo "=== done ==="
