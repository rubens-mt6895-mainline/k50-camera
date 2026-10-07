#!/bin/sh
# zz_macro_grab.sh [frames] - capture macro frames to /root/macro.yuyv (assumes
# zz_macro_cap.sh already brought the GC02M1 pipeline up).
set -u
FR=${1:-4}
OUT=/root/macro.yuyv
rm -f $OUT
echo "=== macro grab: $FR frames ==="
grep -E '^(avg|timing|dist|stats)' /proc/camcap_info | tail -4
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$FR --stream-to=$OUT 2>&1 | tail -3
ls -l $OUT
grep -E '^(avg|timing|dist|stats)' /proc/camcap_info | tail -4
echo "=== done ==="
