#!/bin/sh
# zz_app_install.sh - report the running session + what camera packages exist,
# then install v4l-utils and a camera app.  Device side, run over ssh, nice'd.
export DEBIAN_FRONTEND=noninteractive

echo "=== sessions / GUI ==="
loginctl list-sessions 2>&1 | head -6
who 2>&1 | head
ls /run/user/ 2>&1
ps -eo pid,user,comm 2>/dev/null | grep -Ei 'kwin|plasmashell|Xwayland|gdm|sddm|pipewire' | head -10

echo "=== apt update ==="
nice -n 19 apt-get update -o Acquire::Retries=3 2>&1 | tail -3

echo "=== candidates ==="
apt-cache policy v4l-utils cheese gnome-snapshot gnome-camera kamoso 2>&1 \
	| grep -E '^[a-z0-9-]+:|Candidate:' | head -24
echo "=== done ==="
