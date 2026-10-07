#!/bin/sh
# zz_cheese_media.sh - list what cheese has recorded, and what can decode it.
echo "=== cheese media dir ==="
ls -l /home/k50/.gnome2/cheese/media/ 2>&1 | tail -12
echo "--- totals ---"
ls /home/k50/.gnome2/cheese/media/*.webm 2>/dev/null | wc -l
du -sh /home/k50/.gnome2/cheese/media 2>/dev/null

echo "=== decoders on device ==="
for t in ffmpeg ffprobe gst-launch-1.0 gst-discoverer-1.0; do
	p=$(command -v $t 2>/dev/null)
	echo "  $t: ${p:-no}"
done
apt-cache policy ffmpeg 2>&1 | grep -E '^ffmpeg:|Candidate:'

echo "=== running cheese ==="
pgrep -a cheese 2>&1
echo "=== camcap ==="
grep -E 'frame_ready|arm_count|last_seq|vf_on' /proc/camcap_info 2>&1
echo "=== done ==="
