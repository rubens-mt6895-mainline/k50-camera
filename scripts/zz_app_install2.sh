#!/bin/sh
# zz_app_install2.sh - install v4l-utils, then interrogate /dev/video0 and the
# permissions the desktop user (k50) would get.
export DEBIAN_FRONTEND=noninteractive

echo "=== desktop user ==="
id k50 2>&1
getent group video 2>&1
ls -l /dev/video0 2>&1
getfacl -p /dev/video0 2>/dev/null

echo "=== install v4l-utils ==="
nice -n 19 apt-get install -y --no-install-recommends v4l-utils 2>&1 | tail -5

echo "=== v4l2-ctl --list-devices ==="
v4l2-ctl --list-devices 2>&1

echo "=== v4l2-ctl -d /dev/video0 --all ==="
v4l2-ctl -d /dev/video0 --all 2>&1 | head -60
echo "=== done ==="
