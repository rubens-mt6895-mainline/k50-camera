#!/bin/sh
# zz_dev_survey.sh - what is on the device for a boot-time camera service?
echo "=== /root/*.sh ==="
ls -l /root/*.sh 2>/dev/null
echo "=== /root/v4l2 ==="
ls -l /root/v4l2 2>/dev/null | head -20
echo "=== /root/*.ko ==="
ls -l /root/*.ko 2>/dev/null
echo "=== existing camera-ish units ==="
systemctl list-unit-files 2>/dev/null | grep -i -E 'cam|cheese|v4l2' || echo "  (none)"
echo "=== is any camera unit active? ==="
systemctl list-units 2>/dev/null | grep -i -E 'cam|cheese' || echo "  (none)"
echo "=== loaded modules ==="
lsmod | grep -E 'cam_|videobuf2|videodev|^mc|imx|seninf' | head -20
echo "=== /dev/video0 ==="
ls -l /dev/video0 2>/dev/null || echo "  absent"
echo "=== cheese ==="
which cheese; dpkg -l cheese 2>/dev/null | tail -2
echo "=== who has video0 ==="
fuser -v /dev/video0 2>&1 | head -5
echo "=== welcome/autostart for k50 ==="
ls -l /home/k50/.config/autostart 2>/dev/null || echo "  no autostart dir"
