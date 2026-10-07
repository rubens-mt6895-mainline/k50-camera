#!/bin/sh
# zz_webm_frame.sh - pull one decoded frame out of the video cheese recorded,
# so the app-level capture can be inspected off-device.
export DEBIAN_FRONTEND=noninteractive

echo "=== gstreamer tools ==="
if ! command -v gst-launch-1.0 >/dev/null 2>&1; then
	nice -n 19 apt-get install -y --no-install-recommends gstreamer1.0-tools 2>&1 \
		| grep -viE 'mandb|^$' | tail -3
fi
command -v gst-launch-1.0

F=$(ls -t /home/k50/.gnome2/cheese/media/*.webm 2>/dev/null | head -1)
echo "=== newest recording: $F ==="
ls -l "$F"

echo "=== discover ==="
timeout 60 nice -n 19 gst-discoverer-1.0 "$F" 2>&1 | grep -vE '^\s*$' | head -30

echo "=== decode 3 frames ==="
rm -f /tmp/cf_*.png
timeout 120 nice -n 19 gst-launch-1.0 -q filesrc location="$F" ! decodebin ! videoconvert \
	! pngenc ! multifilesink location=/tmp/cf_%03d.png max-files=3 2>&1 | tail -5
ls -l /tmp/cf_*.png 2>&1
cp -f /tmp/cf_002.png /root/cheese_frame.png 2>/dev/null || cp -f /tmp/cf_001.png /root/cheese_frame.png 2>/dev/null
ls -l /root/cheese_frame.png 2>&1
echo "=== done ==="
