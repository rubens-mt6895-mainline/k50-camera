#!/bin/bash
# Camera bus scan: map i2c-N to its MMIO base, scan every bus, and compare the
# responders against what the vendor DT says should be there.
set -u
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -i ${HOME}/.ssh/${K50_KEY} root@${K50_HOST}"

echo "=== i2c adapters and their MMIO base ==="
$SSH "
for d in /sys/class/i2c-adapter/i2c-*; do
  n=\$(basename \$d)
  p=\$(readlink -f \$d)
  base=\$(echo \"\$p\" | grep -oE '[0-9a-f]{8}\.i2c' | head -1 | cut -d. -f1)
  printf '%-8s base=%-10s %s\n' \"\$n\" \"\${base:-?}\" \"\$(cat \$d/name 2>/dev/null)\"
done
"

echo
echo "=== i2c-tools present? ==="
$SSH "command -v i2cdetect i2cget || echo 'MISSING i2c-tools'"

echo
echo "=== scanning every 11d0xxxx bus (expect 0x10 0x2d 0x37 0x35 0x66 0x51 0x52 0x50 0x28 0x0c) ==="
$SSH "
for d in /sys/class/i2c-adapter/i2c-*; do
  n=\$(basename \$d | sed 's/i2c-//')
  p=\$(readlink -f \$d)
  case \"\$p\" in
    *11d0*) ;;
    *) continue ;;
  esac
  base=\$(echo \"\$p\" | grep -oE '[0-9a-f]{8}\.i2c' | head -1 | cut -d. -f1)
  echo \"--- i2c-\$n  (base 0x\$base) ---\"
  i2cdetect -y -r \$n 2>&1 | tail -9
done
"

echo
echo "=== vcam_ldo (GPIO158) state ==="
$SSH "grep -iE 'vcam|vusb33' /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | head -10"

echo
echo "=== camera GPIOs ==="
$SSH "for g in 158; do printf 'gpio%s: ' \$g; cat /sys/kernel/debug/gpio 2>/dev/null | grep -E \"gpio-\$g\b\" | head -1; echo; done"

echo
echo "=== any camera-ish probe messages / i2c errors ==="
$SSH "dmesg | grep -iE '11d03000|11d06000|fan53870|imgsensor|imx|i2c.*timeout|i2c.*error' | tail -20"
echo "CAMSCAN_DONE"