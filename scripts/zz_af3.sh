#!/bin/sh
# Probe 1: torch LED availability + install the new module (park + wobble counter).
echo "=== LEDs ==="
ls /sys/class/leds/ 2>/dev/null
echo "=== flash/torch ==="
ls -l /sys/class/leds/*flash* /sys/class/leds/*torch* 2>/dev/null
echo "=== brightness nodes ==="
for d in /sys/class/leds/*/; do
  [ -f "$d/brightness" ] && printf '  %s = %s (max %s)\n' "$d" "$(cat $d/brightness 2>/dev/null)" "$(cat $d/max_brightness 2>/dev/null)"
done
echo "=== v4l2 flash devices ==="
ls /dev/v4l-subdev* 2>/dev/null; ls /sys/class/video4linux/ 2>/dev/null

echo "=== install new module ==="
[ -f /root/cam_cap.ko.new ] || { echo "no cam_cap.ko.new"; exit 1; }
cp -f /root/cam_cap.ko /root/cam_cap.ko.v2 2>/dev/null
cp -f /root/cam_cap.ko.new /root/cam_cap.ko
md5sum /root/cam_cap.ko /root/cam_cap.ko.v2 /root/cam_cap.ko.old 2>/dev/null

pkill -x cheese 2>/dev/null
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>/dev/null && echo "rmmod ok"
sh /root/zz_cam_up.sh > /tmp/up.log 2>&1
echo "zz_cam_up rc=$?"
[ -e /dev/video0 ] || { echo "video0 missing, direct insmod"; insmod /root/cam_cap.ko v4l2_enable=1; sleep 2; }

echo "=== af line (new build) ==="
grep -E '^af ' /proc/camcap_info
echo "=== park command ==="
echo park > /proc/camcap
echo "park rc=$?"
sleep 1
grep -E '^af ' /proc/camcap_info
dmesg | tail -3
echo "=== done ==="
