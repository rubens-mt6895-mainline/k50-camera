#!/bin/sh
# zz_macro_probe.sh - what the running kernel/DT offers for the macro camera:
# its I2C bus (i2c4 / 0x11d03000), the pin mux functions we need, and whether
# device-tree overlays are available.
set -u
P=/sys/kernel/debug/pinctrl
echo "=== i2c nodes in the live DT ==="
for d in /proc/device-tree/soc/i2c@*; do
	[ -e "$d" ] || continue
	st=$(tr -d '\0' < "$d/status" 2>/dev/null)
	echo "  $(basename "$d"): status=${st:-<none>}"
done
echo "=== does 11d03000 exist? ==="
ls -d /proc/device-tree/soc/i2c@11d03000 2>&1
echo "=== /dev/i2c-* ==="
ls /dev/i2c-* 2>&1
echo "=== overlay support ==="
ls -d /sys/kernel/config/device-tree/overlays 2>&1
ls /sys/kernel/config/device-tree/overlays/ 2>&1 | head -5
lsmod | grep -E 'cam_ovl|of_overlay|overlay' || echo "  (no overlay module loaded)"
echo "=== pins 137/138/151/154 in pinmux-pins ==="
for p in 137 138 151 154; do
	grep -h "pin $p " "$P"/*/pinmux-pins 2>/dev/null | head -2
done
echo "=== functions mentioning SCL4 / SDA4 / CMMCLK1 / CAMTG2 ==="
for pat in SCL4 SDA4 CMMCLK1; do
	echo "  -- $pat"
	grep -h -o "function [0-9]*: .*$pat[^ ]*" "$P"/*/pinmux-functions 2>/dev/null | head -3
	grep -h -n "$pat" "$P"/*/pinmux-functions 2>/dev/null | head -2
done
echo "=== regulator/gpio state that matters ==="
for g in 144 151 154; do
	echo "  gpio$g: $(cat /sys/kernel/debug/gpio 2>/dev/null | grep -E "gpio-$g " | head -1)"
done
echo "=== zz_macro_probe done ==="
