#!/bin/sh
# Settle the YUYV chroma byte order (and the declared CFA grid) without eyes.
#
# YUYV is Y0 Cb Y1 Cr.  With the AWB switched off, a *known* gain asymmetry has
# to show up in the matching chroma slot: byte 1 (Cb) goes below 128 when blue
# is boosted, byte 3 (Cr) goes above 128 when red is boosted.
#
# Which control drives which physical tap is a direct code fact: red_balance
# writes cam_wb_r_cur, which builds cam_lut_r, which the conversion applies to
# whichever tap rb_swap calls red -- the (0,0) tap when rb_swap=0, the (1,1)
# tap when rb_swap=1.  So "physical R x2, physical B x1" means
#
#	rb_swap=0 (declares RGGB):  red_balance=512 blue_balance=256
#	rb_swap=1 (declares BGGR):  blue_balance=512 red_balance=256
#
# Either way the picture must come out *red*, and on a correct wire that is
# byte3 (Cr) > 128 > byte1 (Cb).  If instead byte1 is the one above 128, the
# kernel is putting Cr in the Cb slot and the scene is being read as blue.
#
# The old (currently loaded) build is captured first so the same physical
# manipulation can be compared across the two builds.
set -u
PARAM=/sys/module/cam_cap/parameters
KO=/root/cam_cap.ko

say() { echo; echo "=== $* ==="; }

stop_consumers() {
	pkill -x cheese 2>/dev/null
	sleep 0.5
	fuser -k /dev/video0 2>/dev/null
	sleep 0.5
}

# usage: cast <tag> <rb_swap> <red_balance> <blue_balance>
cast() {
	tag=$1; rb=$2; rr=$3; bb=$4
	echo "$rb" > $PARAM/rb_swap
	v4l2-ctl -d /dev/video0 -c white_balance_automatic=0 >/dev/null 2>&1
	sleep 0.2
	v4l2-ctl -d /dev/video0 -c red_balance=$rr >/dev/null 2>&1
	v4l2-ctl -d /dev/video0 -c blue_balance=$bb >/dev/null 2>&1
	sleep 1
	say "$tag  rb_swap=$rb red_balance=$rr blue_balance=$bb"
	v4l2-ctl -d /dev/video0 --list-ctrls 2>/dev/null |
		grep -E 'red_balance|blue_balance|white_balance_automatic'
	timeout 90 nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=6 \
		--stream-to=/root/$tag.yuyv >/dev/null 2>&1
	ls -l /root/$tag.yuyv 2>/dev/null || echo "!! capture failed for $tag"
	grep -E 'stats|mean|avg' /proc/camcap_info | head -4
}

stop_consumers

say "loaded module, before any reload"
for p in rb_swap wb_r_q8 wb_b_q8; do echo -n "$p = "; cat $PARAM/$p; done
ls -l /root/cam_cap.ko

say "OLD build, physical R x2 via blue_balance (it declares BGGR)"
cast old_rb1_physR 1 256 512

say "reload with the fixed build"
rmmod cam_cap 2>/dev/null
if grep -q '^cam_cap ' /proc/modules; then
	echo "!! cam_cap still loaded, aborting"
	cat /proc/loadavg
	exit 1
fi
insmod $KO v4l2_enable=1 conv_threads=4 pipeline=1 || { echo "!! insmod failed"; exit 1; }
dmesg | grep -E 'pipeline|cam_cap: loaded|cacheable' | tail -6
dmesg -c >/dev/null
for p in rb_swap wb_r_q8 wb_b_q8; do echo -n "$p = "; cat $PARAM/$p; done

say "NEW build, physical R x2 via red_balance (it declares RGGB)"
cast new_rb0_physR 0 512 256

say "NEW build, the same controls read through the other grid (physical B x2)"
cast new_rb1_physB 1 512 256

say "auto white balance back on, ordinary frames"
echo 0 > $PARAM/rb_swap
v4l2-ctl -d /dev/video0 -c white_balance_automatic=1 >/dev/null 2>&1
sleep 2
timeout 90 nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=8 \
	--stream-to=/root/fixed_auto.yuyv >/dev/null 2>&1
grep -E 'avg|stats|mean' /proc/camcap_info | head -6
timeout 90 nice -n 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=40 \
	--stream-to=/dev/null 2>&1 | tail -2

say "crash scan"
dmesg | grep -icE 'oops|BUG:|panic|Unable to handle|Call trace'
cat /proc/loadavg
