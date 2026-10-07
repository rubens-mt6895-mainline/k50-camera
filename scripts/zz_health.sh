#!/bin/sh
# zz_health.sh - read-only final health snapshot: camera state, module identity,
# liveness, and a crash scan.  Safe to run at any time; touches nothing.
set -u
echo "== time =="; date; uptime
echo "== camera module =="
grep -E '^cam_cap ' /proc/modules || echo "  cam_cap NOT loaded"
ls -l /root/cam_cap.ko /dev/video0 2>&1
md5sum /root/cam_cap.ko 2>/dev/null
echo "== sensor mode / geometry =="
grep -E '^(mode|source|convert|buffer|v4l2|pipe|timing|avg|dist)' /proc/camcap_info | head -20
echo "== last stats =="
grep -E '^(stats|ae|awb)' /proc/camcap_info | head -6
echo "== crash scan (dmesg) =="
dmesg | grep -icE 'oops|BUG:|panic|Call trace'
echo "== users =="
pgrep -x cheese >/dev/null && echo "  cheese RUNNING" || echo "  cheese not running"
echo "== load =="
cat /proc/loadavg
echo "### zz_health done"
