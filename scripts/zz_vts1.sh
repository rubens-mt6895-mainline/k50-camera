#!/bin/sh
# zz_vts1.sh <vts_lines> [burst_n] - retune VTS in the live sensor mode and read
# back the bare arm ceiling, to separate "HTS/pclk is what the table says" from
# "the sensor clamps the line time".
# The sensor write must be a single 4-byte transfer (one data byte no-ops).
V=$1
N=${2:-8}
HI=$(( (V >> 8) & 0xff ))
LO=$(( V & 0xff ))
printf "=== VTS %d -> reg 0x%02x 0x%02x ===\n" "$V" "$HI" "$LO"
i2ctransfer -f -y 10 w4@0x10 0x03 0x40 $HI $LO
sleep 0.3
echo "  readback: $(i2ctransfer -f -y 10 w2@0x10 0x03 0x40 r2 2>&1)"
echo "  HTS 0x0342/43: $(i2ctransfer -f -y 10 w2@0x10 0x03 0x42 r2 2>&1)"
echo "  pll 0x0307: $(i2ctransfer -f -y 10 w2@0x10 0x03 0x07 r1 2>&1)"
dmesg -c >/dev/null 2>&1
echo "burst $N" > /proc/camcap
sleep 5
dmesg | grep -E 'burst:' | tail -1
echo "=== zz_vts1 done ==="
