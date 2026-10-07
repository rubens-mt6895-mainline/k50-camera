#!/bin/sh
# zz_v73.sh -- device side: locate the sensor I2C bus + verify fixed rx71 sticks
echo "=== date/uptime ==="
date; uptime
echo "=== lsmod ==="
lsmod

echo "=== i2cdetect -l ==="
i2cdetect -l 2>&1
echo "=== /dev/i2c-* ==="
ls -l /dev/i2c-* 2>&1

echo "=== full bus scan (only non-empty rows) ==="
for b in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  [ -e /dev/i2c-$b ] || continue
  out=$(i2cdetect -y -r $b 2>&1 | grep -vE '^ *[0-7]0: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --$')
  # count actual device hits (uu)
  hits=$(i2cdetect -y -r $b 2>/dev/null | grep -o 'uu' | wc -l)
  echo "--- bus $b hits=$hits ---"
  [ "$hits" -gt 0 ] && i2cdetect -y -r $b 2>&1
done

echo "=== DT camera sensor nodes ==="
grep -rli "imx582" /proc/device-tree/ 2>/dev/null | head
grep -rli "imx586" /proc/device-tree/ 2>/dev/null | head
echo "(none listed above = no sensor node in DT)"

echo "=== pinmux i2c/cam pins ==="
for f in /sys/kernel/debug/pinctrl/*/pinmux-pins; do
  echo "-- $f"
  grep -iE "152|155|158|159|164|20 |i2c" "$f" 2>/dev/null | head -40
done

echo "=== mclk / camtg clk rates ==="
for f in /sys/kernel/debug/clk/clk_summary; do
  grep -iE "camtg|seninf|mclk|top_seninf" "$f" 2>/dev/null | head -30
done

echo "=== regulators (cam-ish) ==="
cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | grep -iE "ldo|cam|avdd|fan|vmm|dvfs" | head -60

echo "=== gpio debug ==="
cat /sys/kernel/debug/gpio 2>&1 | head -80

echo "=== FIXED port2_rx71 (6s sample) ==="
python3 /root/port2_rx71.py 6 2>&1

echo "=== done ==="
