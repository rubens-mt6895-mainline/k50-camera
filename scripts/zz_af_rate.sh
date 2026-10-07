#!/bin/sh
# zz_af_rate.sh [frames] [on|off] - steady-state fps with the focus search quiet.
#
# With the search enabled every stream start runs a full sweep (39 frames of VCM
# moves), so a plain frame-rate measurement has to turn it off first: this is
# what tells us whether the AF code costs anything when it is idle.
set -u
F="${1:-150}"
AF="${2:-off}"
P=/sys/module/cam_cap/parameters

pkill -x cheese 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1

echo "=== before ==="
grep -E '^af' /proc/camcap_info

if [ "$AF" = "off" ]; then
	echo "af off" > /proc/camcap
else
	echo "af auto" > /proc/camcap
fi
echo "=== conv_threads=$(cat $P/conv_threads) bin=$(cat $P/v4l2_bin) full_cache=$(cat $P/v4l2_full_cache) af=$AF, $F frames ==="
nice -n 10 timeout 240 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count="$F" \
	--stream-to=/dev/null >/dev/null 2>&1

echo
grep -E '^(avg|timing|dist|stats|ae|af|awb)' /proc/camcap_info
echo
echo "=== crash scan (want 0) ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace' || true
cat /proc/loadavg
echo "=== zz_af_rate done ==="
