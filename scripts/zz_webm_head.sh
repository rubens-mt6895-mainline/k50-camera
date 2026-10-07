#!/bin/sh
# zz_webm_head.sh - decode the FIRST frames of each cheese recording (the tail
# frames can be corrupted when a recording is interrupted).
echo "=== recordings ==="
ls -l /home/k50/.gnome2/cheese/media/*.webm 2>&1

for f in $(ls -t /home/k50/.gnome2/cheese/media/*.webm 2>/dev/null); do
	b=$(basename "$f" .webm)
	rm -f /tmp/hd_${b}_*.png
	echo "=== $f ==="
	timeout 180 nice -n 19 gst-launch-1.0 -q filesrc location="$f" ! decodebin \
		! videoconvert ! identity eos-after=4 ! pngenc \
		! multifilesink location=/tmp/hd_${b}_%03d.png max-files=4 2>&1 | tail -3
	ls -l /tmp/hd_${b}_*.png 2>&1
done
echo "=== done ==="
