#!/bin/sh
# zz_af_flat.sh - verify the flat-scene behaviour of the focus search:
# with af_floor above the scene's contrast the scan finds no winner, so the lens
# must go back to where it was and the search must then *stay put* (no periodic
# re-scan), and lowering af_floor must let it search again.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
P=/sys/module/cam_cap/parameters

# a boot may be in progress (the device was just rebooted)
i=0
while [ ! -c /dev/video0 ] && [ "$i" -lt 60 ]; do sleep 5; i=$((i+1)); done
echo "waited $((i*5)) s for /dev/video0"

echo "=== 0. free the device ==="
pkill -x cheese 2>/dev/null
pkill -x guvcview 2>/dev/null
sleep 1
fuser -k /dev/video0 2>/dev/null
sleep 2
rmmod cam_cap 2>&1
dmesg -c >/dev/null

echo
echo "=== 1. bring the stack up with af_trace=1 ==="
sh /root/zz_v80.sh >/dev/null 2>&1
echo "v80 rc=$?"
CAM_CAP_PARAMS="exp_hsize=4000 exp_vsize=3000 out_width=2000 out_height=1500 v4l2_bin=2 conv_threads=8 pipeline=1 af_trace=1" sh /root/zz_cam_up.sh >/dev/null 2>&1
echo "cam_up rc=$?"
dmesg | grep -E 'cam_cap: (source|output|mode|v4l2: registered)' | tail -3

echo
echo "=== 2. park the lens, force 'flat' by raising af_floor above the scene ==="
echo "af pos 512" > /proc/camcap
timeout 150 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=3000 --stream-to=/dev/null >/dev/null 2>&1 &
sleep 3
grep -E '^af ' /proc/camcap_info
echo "--- raise af_floor to 3000 so the current scene counts as flat ---"
echo 3000 > $P/af_floor 2>&1
echo "af_floor now = $(cat $P/af_floor)"
echo "af auto" > /proc/camcap
sleep 12
echo "--- after 12 s of 'flat' auto ---"
grep -E '^af ' /proc/camcap_info
scans1=$(sed -n 's/^af *:.*scans=\([0-9]*\).*/\1/p' /proc/camcap_info)
echo "--- quiet window: 25 s, the lens must not move and scans must not grow ---"
sleep 25
grep -E '^af ' /proc/camcap_info
scans2=$(sed -n 's/^af *:.*scans=\([0-9]*\).*/\1/p' /proc/camcap_info)
echo "scans before=$scans1 after=$scans2"

echo
echo "=== 3. lower af_floor again: the search must react ==="
echo 200 > $P/af_floor 2>&1
sleep 10
grep -E '^af ' /proc/camcap_info
scans3=$(sed -n 's/^af *:.*scans=\([0-9]*\).*/\1/p' /proc/camcap_info)
echo "scans after lowering the floor=$scans3"

echo
echo "=== 4. flat-scene log ==="
dmesg | grep -E 'cam_af' | tail -14
wait

echo
echo "=== 5. restore the defaults for the user ==="
echo 200 > $P/af_floor 2>&1
echo "af pos 512" > /proc/camcap
echo "af auto" > /proc/camcap
sleep 1
grep -E '^af ' /proc/camcap_info
echo "af_floor = $(cat $P/af_floor)"
echo "crashes: $(dmesg | grep -ciE 'oops|BUG:|panic|watchdog')"
uptime
echo "=== zz_af_flat done ==="
