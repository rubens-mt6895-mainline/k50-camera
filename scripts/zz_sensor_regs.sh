#!/bin/sh
# zz_sensor_regs.sh - read the mode/exposure registers off the sensor.
# i2ctransfer takes one byte per argument, so the 16 bit address must be split.
set -u

rd() {
	# rd <reg_hi> <reg_lo> - read two bytes back
	R=$(i2ctransfer -y -f 10 w2@0x10 "$1" "$2" r2 2>&1)
	echo "reg $1$2 = $R"
}

echo "=== stream / readout ==="
rd 0x01 0x00
rd 0x01 0x01
rd 0x01 0x12
echo "=== timing (VTS 0x0340, HTS 0x0342) ==="
rd 0x03 0x40
rd 0x03 0x42
echo "=== exposure / gain (0x0202 exp, 0x0204 again, 0x020e dgain) ==="
rd 0x02 0x02
rd 0x02 0x04
rd 0x02 0x0e
echo "=== clocks ==="
rd 0x03 0x01
rd 0x03 0x05
rd 0x03 0x06
echo "=== load ==="
cat /proc/loadavg
