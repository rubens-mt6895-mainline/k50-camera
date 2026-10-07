#!/bin/sh
# zz_ovl2.sh - read every kernel line about the overlay attempt, then show the
# live DT state of the target node.
echo "=== dmesg: overlay-related ==="
dmesg | grep -i 'overlay' | tail -25
echo "=== dmesg: OF-related ==="
dmesg | grep -iE 'OF:|of_overlay|of_changeset|of_phandle' | tail -25
echo "=== dmesg tail ==="
dmesg | tail -6
echo "=== modules ==="
lsmod | grep -E 'ovl_i2c4' | tr -s ' '
echo "=== zz_ovl2 done ==="
