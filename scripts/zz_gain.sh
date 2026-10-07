#!/bin/sh
# zz_gain.sh -- find the usable analog-gain ceiling (16 ms exposure, dgain 4x).
# Cheap on-device brightness probe: mean of a 64 KiB sample from the middle of the frame
# (avoids pulling 18 MB per try and is bounded so it cannot hog the machine).
IF=/proc/camcap; I2C="i2ctransfer -f -y 10"

w16() { $I2C w4@0x10 0x02 $(printf '0x%02x 0x%02x 0x%02x' $1 $(( $2 >> 8 )) $(( $2 & 0xff ))) >/dev/null 2>&1; }
probe() { dd if=$IF bs=1024 count=64 skip=9216 2>/dev/null | od -An -tu1 | \
          awk '{for(i=1;i<=NF;i++){s+=$i;n++}} END{printf "mean=%.3f n=%d\n", s/n, n}'; }

echo "exposure -> 0x0380 (16 ms)"
w16 0x02 0x0380
w16 0x0e 0x0400            # dgain 4x
for g in 0x00f0 0x01e0 0x03c0 0x0f00 0x3f00; do
  w16 0x04 $g
  echo "cfg 1 0 4000 0 3000 6000 3000 6000" > $IF 2>/dev/null
  echo arm > $IF 2>/dev/null
  sleep 4
  printf "  again=%s  %s  %s\n" "$g" "$(probe)" \
     "$(grep -E 'frame_ready|last_result' /proc/camcap_info | tr -d '\n')"
done
echo "--- done ---"
