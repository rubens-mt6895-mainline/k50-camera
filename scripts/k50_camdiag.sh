#!/bin/bash
# Where do the i2c adapters live on this kernel, and who owns GPIO158?
set -u
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o LogLevel=ERROR -i ${HOME}/.ssh/${K50_KEY} root@${K50_HOST}"
OUT=${K50_REPO}/out/camdiag.txt
: > "$OUT"
{
echo "=== /dev/i2c-* ==="
$SSH "ls -l /dev/i2c-* 2>&1 | head -20"

echo
echo "=== /sys/bus/i2c/devices ==="
$SSH "ls /sys/bus/i2c/devices/ 2>&1 | head -30"

echo
echo "=== /sys/class/ contents (i2c?) ==="
$SSH "ls /sys/class/ | grep -i i2c || echo '  no i2c class'"

echo
echo "=== i2c-adapter in the DTB / driver bound? ==="
$SSH "ls /sys/bus/platform/devices/ | grep -E '11d0' "
$SSH "for d in /sys/bus/platform/devices/11d0*; do printf '%-28s ' \$d; basename \$(readlink -f \$d/driver 2>/dev/null) 2>/dev/null || echo '(no driver)'; done"

echo
echo "=== i2cdetect on the 5 camera buses by device node ==="
$SSH "for n in 8 9 10 11 12 13; do [ -e /dev/i2c-\$n ] || continue; echo \"--- /dev/i2c-\$n ---\"; i2cdetect -y -r \$n 2>&1 | tail -9; done"

echo
echo "=== which i2c-N maps to 11d0xxxx (via /sys/bus/i2c/devices) ==="
$SSH "for l in /sys/bus/i2c/devices/i2c-*; do printf '%-40s -> %s\n' \$l \$(readlink -f \$l); done"

echo
echo "=== GPIO158 owner ==="
$SSH "grep -E 'gpio-158|gpio-135|gpio-3\b' /sys/kernel/debug/gpio"
$SSH "dmesg | grep -iE 'gpio-158|158' | head -10"
} >> "$OUT" 2>&1
echo "CAMDIAG_DONE" >> "$OUT"