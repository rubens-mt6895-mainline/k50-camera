#!/bin/sh
# zz_fan.sh -- FAN53870 dump on the CORRECT bus/address: i2c-11 @ 0x35
echo "=== date ==="; date
echo "=== i2cdetect bus 11 ==="
i2cdetect -y -r 11
echo "=== FAN53870 register dump (i2c-11 @ 0x35) ==="
r=0
while [ $r -le 48 ]; do
  h=$(printf '0x%02x' $r)
  v=$(i2ctransfer -f -y 11 w1@0x35 $h r1 2>&1)
  echo "  $h = $v"
  r=$((r+1))
done
echo "=== main camera bus 10 (sensor 0x10 / af 0x0c / eeprom 0x51) ==="
i2cdetect -y -r 10
for a in 0x10 0x0c 0x51; do
  echo "  probe $a:"
  i2ctransfer -f -y 10 w1@$a 0x00 r1 2>&1
done
echo "=== done ==="
