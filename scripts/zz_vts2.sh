#!/bin/sh
# zz_vts2.sh -- shrink VTS far below the vendor default in the *current* sensor mode
# and watch the burst period.  If the period stays put, the per-frame floor is NOT
# the sensor's frame-length register (it is either the sensor's readout limit or our
# CAMSV/DMA path).  Live i2ctransfer writes with -f (we do not own the adapter, but
# the driver only touches 0x0202/0x0204/0x020e while streaming -- and burst does not
# run the governor, so nothing overwrites VTS behind our back).
# usage: zz_vts2.sh
set -x
P=/sys/module/cam_cap/parameters
w16() { i2ctransfer -y -f 10 w4@0x10 "$1" "$2" "$3" "$4" 2>&1; }
r16() { i2ctransfer -y -f 10 w2@0x10 "$1" "$2" r2@0x10 2>&1; }

echo "=== live: vts $(r16 0x03 0x40) exp $(r16 0x02 0x02)"
for v in 1236 900 600 300 1236; do
    hi=$((v >> 8)); lo=$((v & 255))
    echo "=== VTS $v -> $hi $lo"
    w16 0x03 0x40 "$hi" "$lo"
    echo "  readback: $(r16 0x03 0x40)"
    echo "burst 8" > /proc/camcap
done
echo "=== restored: vts $(r16 0x03 0x40)"
echo "zz_vts2 done"
