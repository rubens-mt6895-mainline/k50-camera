#!/bin/sh
# zz_af_up.sh [module params...] - reload cam_cap with the AE-smoothing + VCM
# autofocus build.
#
# This is the one disruptive step of the round: rmmod needs the vb2 handle
# closed, so a running Cheese stream ends here.  Everything else this round
# changed (AE IIR + symmetric log step, the VCM/AF subsystem) rides in with that
# single reload.
#
#   sh /root/zz_af_up.sh                 # defaults (autofocus on)
#   sh /root/zz_af_up.sh af_auto=0       # VCM up, search held (manual sweep)
set -u

PARAMS="$*"

echo "=== before ==="
date
if pgrep -x cheese >/dev/null 2>&1; then
	echo "  cheese is streaming; it will be stopped for the reload"
fi
grep -E '^af ' /proc/camcap_info 2>/dev/null || echo "  (no af line: this is the old module)"

echo
echo "=== load (extra params: ${PARAMS:-(none)}) ==="
CAM_CAP_PARAMS="$PARAMS" sh /root/zz_cam_up.sh 2>&1 | \
	grep -E '\[ok\]|\[!!\]|name:|af_|vcm_|v4l2_bin|v4l2_full_cache|conv_threads|exp_max|pipeline' | tail -30

echo
echo "=== dmesg: VCM ==="
dmesg | grep -E 'VCM|cam_cap: source' | tail -10

echo
echo "=== af line ==="
grep -E '^af' /proc/camcap_info

echo
echo "=== crash scan (want 0) ==="
dmesg | grep -ciE 'Unable to handle|Internal error|Oops|BUG:|call trace'
cat /proc/loadavg
echo "=== zz_af_up done ==="
