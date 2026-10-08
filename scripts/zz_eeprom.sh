#!/bin/sh
# READ-ONLY: dump the camera module EEPROM (0x51, bus 10) to look for MTK's AF calibration block.
echo "=== try 2-byte offset addressing (16 bytes per page, pages 0..7) ==="
for pg in 0 1 2 3 4 5 6 7; do
  off=$((pg*16))
  printf 'off 0x%03x: ' "$off"
  i2ctransfer -y -f 10 w2@0x51 $((off>>8)) $((off&0xff)) r16 2>&1 | head -1
done
echo "=== try 1-byte offset addressing (16 bytes, offset 0) ==="
printf 'off 0x00: '
i2ctransfer -y -f 10 w1@0x51 0x00 r16 2>&1 | head -1
printf 'off 0x10: '
i2ctransfer -y -f 10 w1@0x51 0x10 r16 2>&1 | head -1
echo "=== printable strings in the first 256 bytes (2-byte addr) ==="
{
  for pg in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    off=$((pg*16))
    i2ctransfer -y -f 10 w2@0x51 $((off>>8)) $((off&0xff)) r16 2>/dev/null
  done
} | tr -d '\n' | sed 's/0x//g' | tr ' ' '\n' | grep -E '^[0-9a-f]{2}$' | tr '\n' ' '
echo
echo "=== done ==="
