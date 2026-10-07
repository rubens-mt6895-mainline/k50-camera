#!/bin/sh
# zz_recon_cam.sh -- lightweight reconnaissance: can this device host a normal camera stack?
echo "=== 1. OS / init ==="
cat /etc/os-release 2>/dev/null | head -4
echo "default target: $(systemctl get-default 2>/dev/null)"
echo "kernel: $(uname -r)"

echo "=== 2. display / desktop ==="
ps -e -o comm= 2>/dev/null | grep -iE 'gnome-shell|weston|Xorg|wayland|kwin|phosh|sway|labwc|xfwm|mutter' | head -8
echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset} DISPLAY=${DISPLAY:-unset} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
ls -l /dev/fb0 /dev/dri/card0 2>&1 | head -4

echo "=== 3. camera applications ==="
for a in cheese snapshot guvcview cameractl pipewire wireplumber v4l2-ctl gst-launch-1.0 ffmpeg libcamera-hello qcam; do
  p=$(command -v $a 2>/dev/null) && echo "  $a -> $p"
done
echo "  (dpkg camera-ish packages:)"
dpkg -l 2>/dev/null | awk '/^ii/ && /cheese|snapshot|gstreamer|v4l|pipewire|libcamera/ {print "    "$2" "$3}' | head -20

echo "=== 4. V4L2 present? ==="
ls -l /dev/video* 2>&1 | head -6
echo "  /sys/class/video4linux: $(ls /sys/class/video4linux/ 2>&1 | tr '\n' ' ')"
echo "  /dev/media*: $(ls /dev/media* 2>&1 | tr '\n' ' ')"
echo "  /proc/devices video: $(grep -i -E 'video|media' /proc/devices 2>/dev/null | tr '\n' ' ')"
echo "  loaded video modules: $(lsmod | awk '/v4l|videobuf|videodev|media/ {printf "%s ",$1}')"

echo "=== 5. package manager / network ==="
for a in apt apt-get dpkg gcc make python3; do p=$(command -v $a 2>/dev/null) && echo "  $a -> $p"; done
echo "  apt sources: $(head -2 /etc/apt/sources.list 2>/dev/null | tr '\n' ' ')"
echo "  ping deb.debian.org: $(ping -c1 -W3 deb.debian.org 2>&1 | tail -2 | tr '\n' ' ')"
echo "  ip: $(ip -4 -o addr show 2>/dev/null | awk '{print $2"="$4}' | tr '\n' ' ')"
echo "=== recon done ==="
