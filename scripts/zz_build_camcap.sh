#!/bin/bash
# zz_build_camcap.sh - rebuild cam_cap.ko against the device-matched kernel tree and show the result.
# (Sources were tidied into scripts/ + src/, so this wrapper now points at both
#  the real script location and the real source directory.)
cd ${K50_REPO} || exit 1
export K=${KDIR}
export OUT=${K50_REPO}/out/camcap_0b8dd2e
export SRC=${K50_REPO}/src
bash ${K50_REPO}/scripts/z_build_camcap.sh 2>&1 | tail -30
echo "--- artifact ---"
ls -l out/camcap_0b8dd2e/cam_cap.ko
echo "--- modinfo ---"
modinfo out/camcap_0b8dd2e/cam_cap.ko 2>/dev/null | grep -E "vermagic|^parm"
