#!/bin/sh
# zz_nodes3.sh [frames] - SAFE multi-node verification after the 2026-10-09 hang.
#
# Rules: never let one camera's live bring-up be followed by an implicit engine
# switch.  Every "which camera is streaming" transition goes through a fresh
# module load (rmmod + insmod), and the refusal path is exercised with no
# auxiliary camera powered at all.
FR=${1:-40}
P=/sys/module/cam_cap/parameters
G=/root/gpiotoolG
STATE=/proc/camcap_info

say() { echo; echo "--- $* ---"; }

say "0. health"
date; uptime; free | grep -i cma
echo "mod: $(md5sum /root/cam_cap.ko | cut -c1-32)"
fuser -v /dev/video* 2>&1 | head -5

say "1. module load with four nodes (main camera stack, cam_nodes=4)"
pkill -x cheese 2>/dev/null
if grep -q '^cam_cap' /proc/modules; then
	rmmod cam_cap || { echo "ABORT: rmmod failed"; exit 1; }
fi
CAM_V80_NO_INSMOD=1 sh /root/zz_v80.sh >/dev/null 2>&1
CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh || { echo "ABORT: insmod failed"; exit 1; }
dmesg -c >/dev/null
ls -l /dev/video0 /dev/video1 /dev/video2 /dev/video3 2>&1 | sed 's/  */ /g'
for n in 0 1 2 3; do
	printf "video%s card: " "$n"
	v4l2-ctl -d /dev/video$n --info 2>/dev/null | grep -i 'card type' | head -1
done

say "2. node 0 alone (must be the main camera, route intf 4)"
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$FR --stream-to=/dev/null >/dev/null 2>&1
echo "rc=$?"
grep -E '^(avg|timing|dist|stats|route)' $STATE | head -8
echo "timeouts: $(dmesg | grep -c 'timed out')"

say "3. refusal path, no auxiliary camera powered"
# s_fmt on node 1 only moves the engine's board pointer (and clears
# cam_route_done); nothing is streamed from it, so no route register is written.
v4l2-ctl -d /dev/video1 --set-fmt-video=width=1296,height=976,pixelformat=YUYV >/dev/null 2>&1
echo "node1 s_fmt rc=$?  (engine board is now IMX596)"
echo "attempting node 0 stream, expect -EBUSY and no arm:"
timeout 25 v4l2-ctl -d /dev/video0 --stream-mmap=4 --stream-count=5 --stream-to=/dev/null 2>&1 | tail -2
echo "rc=$?"
dmesg | grep -i 'node 0 refused' | tail -2
echo "timeouts: $(dmesg | grep -c 'timed out')"

say "4. node 0 again after a fresh module load (cam_nodes=4, no aux camera used)"
rmmod cam_cap || { echo "ABORT: rmmod failed"; exit 1; }
CAM_CAP_PARAMS="cam_nodes=4" sh /root/zz_cam_up.sh || { echo "ABORT: insmod failed"; exit 1; }
dmesg -c >/dev/null
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$FR --stream-to=/dev/null >/dev/null 2>&1
echo "rc=$?"
grep -E '^(avg|timing|dist|stats)' $STATE | head -5

say "5. restore the default single-node stack"
rmmod cam_cap || echo "rmmod failed"
sh /root/zz_cam_up.sh >/dev/null 2>&1
dmesg -c >/dev/null
timeout 40 v4l2-ctl -d /dev/video0 --stream-mmap=8 --stream-count=$FR --stream-to=/dev/null >/dev/null 2>&1
echo "rc=$?"
grep -E '^(avg|timing|dist|stats)' $STATE | head -5
ls /dev/video* 2>&1

say "6. health"
dmesg | grep -icE 'call trace|Oops|panic|BUG:'
echo "timeouts: $(dmesg | grep -c 'timed out')"
cat /proc/loadavg
pgrep -ax v4l2-ctl | head -3
pgrep -ax cheese | head -3
echo "done"
