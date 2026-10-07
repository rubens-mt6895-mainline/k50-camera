#!/bin/bash
# Camera scan, clean: all output into one local file, ssh noise suppressed.
set -u
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o LogLevel=ERROR -i ${HOME}/.ssh/${K50_KEY} root@${K50_HOST}"
OUT=${K50_REPO}/out/camscan.txt
: > "$OUT"

{
echo "=== adapters (map i2c-N -> MMIO base) ==="
$SSH "for d in /sys/class/i2c-adapter/i2c-*; do n=\$(basename \$d); p=\$(readlink -f \$d); b=\$(echo \$p | grep -oE '[0-9a-f]{8}\.i2c' | head -1 | cut -d. -f1); printf '%-8s base=%-10s\n' \$n \${b:-?}; done"

echo
echo "=== scan every 11d0xxxx bus ==="
$SSH "for d in /sys/class/i2c-adapter/i2c-*; do n=\$(basename \$d | sed 's/i2c-//'); p=\$(readlink -f \$d); case \$p in *11d0*) ;; *) continue;; esac; b=\$(echo \$p | grep -oE '[0-9a-f]{8}\.i2c' | head -1 | cut -d. -f1); echo \"--- i2c-\$n (0x\$b) ---\"; i2cdetect -y -r \$n 2>&1 | tail -9; done"

echo
echo "=== vcam / camera regulators ==="
$SSH "grep -iE 'vcam' /sys/kernel/debug/regulator/regulator_summary 2>/dev/null || echo '  (vcam_ldo NOT registered)'"

echo
echo "=== regulator-fixed probe errors in dmesg ==="
$SSH "dmesg | grep -iE 'regulator|vcam|gpio.*158|shared' | tail -25"

echo
echo "=== gpio 150-165 ==="
$SSH "grep -E 'gpio-1(5[0-9]|6[0-5])\b' /sys/kernel/debug/gpio 2>/dev/null"

echo
echo "=== is the 5th bus there? ==="
$SSH "ls -d /sys/bus/platform/devices/11d03000.i2c 2>&1; ls /sys/class/i2c-adapter/ | tail -6"

echo
echo "=== camera-ish dmesg ==="
$SSH "dmesg | grep -iE '11d03000|11d06000|fan53870|imx|imgsensor' | tail -15"
} >> "$OUT" 2>&1
echo "CAMSCAN2_DONE" >> "$OUT"