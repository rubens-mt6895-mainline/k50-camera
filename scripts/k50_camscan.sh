#!/bin/bash
# Full scan of the camera i2c buses and the current USB port state.
for n in 7 8 9 10 11; do
	echo "--- i2c-$n ---"
	timeout 20 i2cdetect -y "$n" 2>&1
done
echo
echo "=== usb state now ==="
printf 'role       = %s\n' "$(cat /sys/class/usb_role/11201000.usb0-role-switch/role 2>/dev/null)"
printf 'data_role  = %s\n' "$(cat /sys/class/typec/port0/data_role 2>/dev/null)"
printf 'power_role = %s\n' "$(cat /sys/class/typec/port0/power_role 2>/dev/null)"
printf 'usb devices= %s\n' "$(ls /sys/bus/usb/devices/ | tr '\n' ' ')"
echo
echo "=== which controller is which bus ==="
for n in 7 8 9 10 11; do
	d=$(readlink -f /sys/bus/i2c/devices/i2c-$n/of_node 2>/dev/null)
	p=/sys/bus/i2c/devices/i2c-$n
	printf 'i2c-%-3s %s\n' "$n" "$(cat $p/name 2>/dev/null)"
done
grep -H . /sys/class/i2c-adapter/i2c-8/name /sys/class/i2c-adapter/i2c-9/name \
	/sys/class/i2c-adapter/i2c-10/name /sys/class/i2c-adapter/i2c-11/name 2>/dev/null
echo
echo "=== the camera controllers' reg bases, from the DT ==="
for n in 8 9 10 11; do
	of=$(readlink /sys/bus/i2c/devices/i2c-$n/of_node 2>/dev/null)
	[ -n "$of" ] && printf 'i2c-%-3s %s\n' "$n" "$of"
done
