#!/bin/sh
# zz_cheese_install.sh - install the GNOME camera app (cheese) on the device.
export DEBIAN_FRONTEND=noninteractive

echo "=== install cheese ==="
nice -n 19 apt-get install -y cheese 2>&1 | grep -viE 'mandb|^$' | tail -8

echo "=== cheese present? ==="
which cheese 2>&1
dpkg -s cheese 2>/dev/null | grep -E '^(Package|Version|Status):'

echo "=== screenshot tools ==="
for t in spectacle grim import flameshot ksnip; do
	p=$(which $t 2>/dev/null)
	echo "  $t: ${p:-no}"
done

echo "=== gstreamer v4l2 bits ==="
ls /usr/lib/*/gstreamer-1.0/libgstvideo4linux2.so /usr/lib/*/gstreamer-1.0/libgstvideo4linux2.so 2>/dev/null
which gst-launch-1.0 gst-inspect-1.0 2>&1
echo "=== done ==="
