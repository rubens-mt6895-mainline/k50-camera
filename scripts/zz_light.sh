#!/bin/sh
# zz_light.sh -- long-exposure test.  VMAX=0x0E4A=3658 lines, line time 17.86us
#   default 0x0202 = 0x0004 lines = 0.07 ms  (why the image was so dark)
#   0x0380 =  896 lines = 16.0 ms
#   0x0E00 = 3584 lines = 64.0 ms  (just under VMAX)
IF=/proc/camcap; I2C="i2ctransfer -f -y 10"

setexp() { $I2C w4@0x10 0x02 0x02 $(printf '0x%02x 0x%02x' $(($1 >> 8)) $(($1 & 0xff))) >/dev/null 2>&1; }

echo "exposure readback before: $($I2C r2@0x10 w2@0x10 0x02 0x02 2>/dev/null | tail -1)"

for e in 0x0004 0x0380 0x0e00; do
  setexp $e
  echo "--- exposure $e ($((e)) lines = $(( e * 17860 / 1000000 )).$(( (e * 17860 / 1000) % 1000 )) ms) ---"
  echo "    readback: $($I2C r2@0x10 w2@0x10 0x02 0x02 2>/dev/null | tail -1)"
  echo "cfg 1 0 4000 0 3000 6000 3000 6000" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 4
  grep -E 'frame_ready|last_result' /proc/camcap_info | tr -d '\n'; echo
  dd if=$IF of=/tmp/exp_$e.bin bs=1M count=19 2>/dev/null
  # mean of the G plane (12-bit) via a tiny python one-liner
  python3 - <<EOF
import numpy as np
d = np.fromfile("/tmp/exp_$e.bin", np.uint8)[:3000*6000].reshape(3000,-1,3).astype(np.uint16)
b0,b1,b2 = d[:,:,0], d[:,:,1], d[:,:,2]
P = np.empty((3000,4000), np.uint16)
P[:,0::2] = b0 | ((b1 & 0x0F) << 8)
P[:,1::2] = (b1 >> 4) | (b2 << 4)
q = np.percentile(P, [1,25,50,75,99])
print("    12bit px: min %d p1 %d p25 %d p50 %d p75 %d p99 %d max %d mean %.1f"
      % (P.min(), q[0], q[1], q[2], q[3], q[4], P.max(), P.mean()))
EOF
done
echo "--- done ---"
