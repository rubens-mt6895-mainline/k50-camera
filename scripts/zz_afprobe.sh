#!/bin/sh
# READ-ONLY probe: which camera I2C buses carry a focus actuator chip?
echo "=== time / uptime ==="
date; uptime
echo "=== who holds /dev/video0 ==="
fuser -v /dev/video0 2>&1 | head -6
echo "=== i2c adapters ==="
i2cdetect -l 2>&1
echo "=== i2c sysfs ==="
for p in /sys/bus/i2c/devices/i2c-*; do
  b=$(basename "$p")
  printf '%s name=%s of=%s\n' "$b" "$(cat "$p/name" 2>/dev/null)" "$(readlink -f "$p/of_node" 2>/dev/null)"
done
echo "=== camera-related modules ==="
lsmod 2>/dev/null | grep -Ei 'cam|ovl|i2c_mt|i2c-mt' 
echo "=== tools ==="
command -v i2cdetect || echo "no i2cdetect"
command -v i2cget || echo "no i2cget"
command -v i2ctransfer || echo "no i2ctransfer"
echo "=== per-bus address map (read-only probing) ==="
for n in 0 1 2 3 4 5 6 7 8 9 10 11 12 13; do
  [ -e /dev/i2c-$n ] || continue
  echo "--- bus $n ---"
  if command -v i2cdetect >/dev/null 2>&1; then
    i2cdetect -y -r $n 2>&1
  else
    # fallback: read reg 0x00 from every address (read transactions only)
    L=""
    a=3
    while [ $a -le 119 ]; do
      if i2ctransfer -y -f $n w1@0x$(printf %02x $a) 0x00 r1 2>/dev/null >/dev/null; then
        L="$L $(printf %02x $a)"
      fi
      a=$((a+1))
    done
    echo "  ACK:$L"
  fi
done
echo "=== main VCM (bus 10, 0x0c) register peek ==="
for r in 0x00 0x01 0x02 0x03 0x04 0x05; do
  printf '  reg %s = ' "$r"
  i2ctransfer -y -f 10 w1@0x0c $r r1 2>&1 | head -2 | tr '\n' ' '
  echo
done
echo "=== camcap af line ==="
grep -E '^(af|source|output|v4l2)' /proc/camcap_info 2>/dev/null | head -8
echo "=== done ==="
