#!/bin/sh
# zz_shot_probe.sh - what screenshot path is available on this KDE Wayland box?
echo "=== tools ==="
for t in gdbus qdbus qdbus-qt5 qdbus6 dbus-send flameshot grim import scrot gnome-screenshot spectacle; do
	p=$(command -v $t 2>/dev/null)
	echo "  $t: ${p:-no}"
done

echo "=== portals ==="
ls /usr/libexec/xdg-desktop-portal* 2>&1
dpkg -l 2>/dev/null | grep -E 'xdg-desktop-portal' | awk '{print "  "$2" "$3}'

echo "=== apt candidates ==="
apt-cache policy flameshot grim scrot imagemagick 2>&1 | grep -E '^[a-z0-9-]+:|Candidate:' | head -20
echo "=== done ==="
