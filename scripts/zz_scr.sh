#!/bin/sh
# zz_scr.sh - recon for the focus-metric A/B: can we light the FRONT camera with
# the phone's own screen, and are the front bring-up pieces on the device?
set -u
echo "=== zz_scr: screen + front-camera bring-up recon ==="
date
echo "--- /root pieces"
for f in sensor_bring.py csirx_bring.py gpiotoolG imx596_init.txt imx596_2592x1952.txt cam_cap.ko cam_cap.ko.old; do
	if [ -e "/root/$f" ]; then
		ls -l "/root/$f"
	else
		echo "MISSING: /root/$f"
	fi
done
echo "--- backlight"
ls -d /sys/class/backlight/* 2>/dev/null || echo "  (no backlight class)"
for b in /sys/class/backlight/*; do
	[ -e "$b/brightness" ] || continue
	echo "  $b"
	echo "    brightness=$(cat $b/brightness 2>/dev/null) actual=$(cat $b/actual_brightness 2>/dev/null) max=$(cat $b/max_brightness 2>/dev/null) bl_power=$(cat $b/bl_power 2>/dev/null)"
done
echo "--- drm connectors"
for c in /sys/class/drm/card*/card*; do
	[ -e "$c/status" ] || continue
	echo "  $(basename $c) status=$(cat $c/status) enabled=$(cat $c/enabled 2>/dev/null) modes=$(cat $c/modes 2>/dev/null | head -1)"
done
echo "--- session"
who 2>/dev/null | head -5
pgrep -a -f 'kwin_wayland|plasmashell|Xwayland|kscreenlocker' 2>/dev/null | head -6
echo "  loginctl:"; loginctl list-sessions 2>/dev/null | head -5
echo "--- gstreamer"
which gst-launch-1.0 2>/dev/null || echo "  no gst-launch-1.0"
gst-inspect-1.0 waylandsink 2>/dev/null | head -3
gst-inspect-1.0 videotestsrc 2>/dev/null | head -3
gst-inspect-1.0 videoconvert 2>/dev/null | head -3
echo "--- gst plugins on disk"
ls /usr/lib/aarch64-linux-gnu/gstreamer-1.0/ 2>/dev/null | head -20
echo "--- python3 gi/gtk present?"
python3 -c "import gi; print('gi ok')" 2>&1 | head -2
echo "--- current /dev/video0 holders"
fuser -v /dev/video0 2>&1 | head -6
echo "--- module state"
grep -E '^cam_cap' /proc/modules || echo "  cam_cap not loaded"
echo "--- uptime / load / temp"
uptime
cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -4
echo "=== done ==="
