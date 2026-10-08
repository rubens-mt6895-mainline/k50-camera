#!/bin/sh
# Soak the default stack (bin2 2000x1500, af_enable=1) for a fixed number of
# frames and report rate, frame-interval distribution, AF activity, temperature
# and health before/after.  This is the "Cheese running for a long time" case.
set -u
N=${1:-12000}

snap() {
	echo "--- $1 ---"
	grep -E '^(avg|timing|dist|stats|af|ae)' /proc/camcap_info 2>/dev/null | cut -c1-160
	echo "load: $(cat /proc/loadavg)"
	echo "temp: $(for z in /sys/class/thermal/thermal_zone*; do [ -f "$z/temp" ] && printf '%s=%s ' "$(cat $z/type 2>/dev/null)" "$(cat $z/temp)"; done)"
	echo "mem : $(grep -E 'MemFree|MemAvailable' /proc/meminfo | tr '\n' ' ')"
	echo "crashes: $(dmesg | grep -icE 'Oops|BUG:|panic|Unable to handle|Internal error')"
}

echo "=== soak: $N frames on the default stack ==="
snap before
start=$(cat /proc/uptime | cut -d' ' -f1)
timeout 900 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=$N --stream-to=/dev/null >/dev/null 2>&1
rc=$?
end=$(cat /proc/uptime | cut -d' ' -f1)
echo "stream rc=$rc  wall=$(awk "BEGIN{printf \"%.1f\", $end - $start}")s for $N frames"
echo "wall fps = $(awk "BEGIN{printf \"%.2f\", $N / ($end - $start)}")"
snap after
echo "=== cam_af trace (last 8) ==="
dmesg | grep 'cam_af:' | tail -8
echo "=== scan/wobble summary ==="
dmesg | grep -c 'cam_af: scan'
dmesg | grep -c 'cam_af: wobble'
