#!/bin/sh
# zz_i2cdiag.sh - why does the driver's I2C write path stay closed?
set -u
echo '--- i2c adapters ---'
for a in /sys/bus/i2c/devices/i2c-*; do
	[ -d "$a" ] || continue
	printf '%s %s\n' "$(basename "$a")" "$(cat "$a/name" 2>/dev/null)"
done
echo '--- dmesg cam_cap ---'
dmesg | grep -i 'cam_cap' | tail -30
echo '--- proc ---'
grep -E 'sensor_i2c|^ae|^awb|^stats' /proc/camcap_info
