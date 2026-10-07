#!/bin/sh
# zz_color.sh -- capture one frame with the best settings found, for colour reconstruction.
IF=/proc/camcap; I2C="i2ctransfer -f -y 10"
w16() { $I2C w4@0x10 0x02 $(printf '0x%02x 0x%02x 0x%02x' $1 $(( $2 >> 8 )) $(( $2 & 0xff ))) >/dev/null 2>&1; }

w16 0x02 0x0380      # exposure 896 lines = 16 ms
w16 0x04 0x0f00      # analog gain (best of the sweep)
w16 0x0e 0x0400      # digital gain 4x
sleep 1
echo "readback 0x0202/0x0204/0x020e:"
$I2C w2@0x10 0x02 0x02 r2@0x10 2>/dev/null
$I2C w2@0x10 0x02 0x04 r2@0x10 2>/dev/null
$I2C w2@0x10 0x02 0x0e r2@0x10 2>/dev/null

echo "cfg 1 0 4000 0 3000 6000 3000 6000" > $IF 2>/dev/null
echo arm > $IF 2>/dev/null
sleep 4
grep -E 'frame_ready|last_result|int_status' /proc/camcap_info
dd if=$IF of=/tmp/color_frame.bin bs=1M count=19 2>/dev/null
echo "nz=$(dd if=/tmp/color_frame.bin bs=1M count=19 2>/dev/null | tr -d '\000' | wc -c)"
echo "md5=$(md5sum /tmp/color_frame.bin | cut -c1-32)"
echo "--- done ---"
