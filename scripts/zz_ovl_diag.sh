#!/bin/sh
# zz_ovl_diag.sh - read the kernel's OF overlay messages after a failed apply.
echo "=== lines mentioning overlay ==="
dmesg | grep -i 'overlay' | tail -30
echo "=== lines starting with OF: ==="
dmesg | grep -F 'OF:' | tail -20
echo "=== dmesg tail ==="
dmesg | tail -12
echo "=== modules ==="
lsmod | grep -E 'ovl_i2c4|cam_ovl'
echo "=== zz_ovl_diag done ==="
