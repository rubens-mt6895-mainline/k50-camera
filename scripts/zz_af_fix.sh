#!/bin/sh
# zz_af_fix.sh - dark-room autofocus regression test.
#
# The bug: in a scene with no measurable contrast the search parked the lens on
# whichever sample noise favoured (or on the first coarse point, DAC 0), and the
# rescan logic then re-ran a scan every few seconds, so the picture kept
# pumping and was often defocused.
#
# The fix under test: a scan that finds no sample at or above af_floor puts the
# lens back where it found it and holds; below the floor there is no wobble and
# the rescan interval is CAMCAP_AF_FLAT_FRAMES.
#
# Acceptance: the "found no contrast, lens back to <pos>" line appears, the af
# line keeps pos=<that position> with flat=1, and no new scan starts during the
# 25 s quiet window.
set -u

P=/sys/module/cam_cap/parameters

echo "=== 0 release the camera ==="
pkill -x cheese 2>/dev/null
pkill -x guvcview 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 1
rmmod cam_cap 2>/dev/null
dmesg -c >/dev/null

echo "=== 1 bring-up (preview, af_trace on) ==="
sh /root/zz_v80.sh >/tmp/v80.log 2>&1 || echo "v80 rc=$?"
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=8 pipeline=1 af_trace=1" \
	sh /root/zz_cam_up.sh >/tmp/up.log 2>&1 || echo "up rc=$?"
dmesg | grep -E "cam_cap: (source|mode|output|convert|pipeline)" | tail -4
echo "floor: $(cat $P/af_floor)  fallback: $(cat $P/af_fallback)"

echo "=== 2 park the lens at 512 (manual, no search) ==="
echo "af pos 512" > /proc/camcap
sleep 2
grep -E "^af" /proc/camcap_info

echo "=== 3 start a stream, in the background ==="
( timeout 120 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=4000 \
	--stream-to=/dev/null >/tmp/stream.log 2>&1 ) &
sleep 6
grep -E "^af" /proc/camcap_info
grep -E "^(avg|stats)" /proc/camcap_info

echo "=== 4 hand the lens to the search (dark scene: nothing measurable) ==="
echo "af auto" > /proc/camcap
sleep 20
grep -E "^af" /proc/camcap_info
echo "--- dmesg af lines ---"
dmesg | grep -E "cam_af" | tail -8
echo "scans so far: $(dmesg | grep -cE 'cam_af: scan')"

echo "=== 5 quiet window: 25 s, no new scan may start ==="
sleep 25
grep -E "^af" /proc/camcap_info
echo "scans now: $(dmesg | grep -cE 'cam_af: scan')"
grep -E "^(avg|timing|stats)" /proc/camcap_info

echo "=== 6 a lit-scene sanity check: does a real sweep see contrast? ==="
echo "af off" > /proc/camcap
sleep 1
for p in 0 256 512 768 1023; do
	echo "af pos $p" > /proc/camcap
	sleep 2
	echo "pos $p -> $(sed -n 's/^af *:.*metric=\([0-9]*\) y=\([0-9]*\).*/metric=\1 y=\2/p' /proc/camcap_info)"
done
echo "af pos 512" > /proc/camcap

echo "=== 7 stop the stream and check health ==="
pkill -x v4l2-ctl 2>/dev/null
sleep 1
dmesg | grep -E "oops|BUG|panic|Call trace" | tail -3
free -m | head -2
uptime
