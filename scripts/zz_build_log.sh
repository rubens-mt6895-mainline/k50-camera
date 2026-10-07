#!/bin/bash
# zz_build_log.sh - build cam_cap.ko and show the compiler diagnostics.
#
# zz_build_camcap.sh tails the last 30 lines of the build, which usually hides
# the one line that matters, so this keeps the whole log and greps it.
#
#   wsl -- bash -lc "bash ${K50_REPO}/scripts/zz_build_log.sh"
#
LOG=${LOG:-/tmp/build_cam.log}
K=${KDIR} \
OUT=${K50_REPO}/out/camcap_0b8dd2e \
SRC=${K50_REPO}/src \
	bash ${K50_REPO}/scripts/z_build_camcap.sh >"$LOG" 2>&1
rc=$?
echo "=== rc=$rc ==="
echo "=== diagnostics ==="
grep -nE 'warning:|error:|Error [0-9]' "$LOG" | head -40
echo "=== tail ==="
tail -8 "$LOG"
exit $rc
