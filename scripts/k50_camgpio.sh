#!/bin/bash
# Is GPIO158 muxed as a GPIO at all, and is vcam_ldo really enabled?
set -u
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o LogLevel=ERROR -i ${HOME}/.ssh/${K50_KEY} root@${K50_HOST}"
OUT=${K50_REPO}/out/camgpio.txt
: > "$OUT"
{
echo "=== regulator summary header + vcam_ldo ==="
$SSH "head -1 /sys/kernel/debug/regulator/regulator_summary; grep -i vcam /sys/kernel/debug/regulator/regulator_summary"

echo
echo "=== vcam_ldo detail in debugfs ==="
$SSH "ls /sys/kernel/debug/regulator/ | grep -i vcam; for f in /sys/kernel/debug/regulator/vcam_ldo/*; do printf '%-50s %s\n' \$f \"\$(cat \$f 2>/dev/null)\"; done"

echo
echo "=== pinmux state of the pin behind GPIO158 ==="
$SSH "for d in /sys/kernel/debug/pinctrl/*pinctrl*; do echo \"-- \$d\"; grep -E 'pin (158|135|3) ' \$d/pinmux-pins 2>/dev/null; done"

echo
echo "=== GPIO158 raw regs via /sys/kernel/debug/gpio (full line) ==="
$SSH "grep -n 'gpio-158' /sys/kernel/debug/gpio"

echo
echo "=== compare: how the touch reset GPIO (working) appears ==="
$SSH "grep -nE 'gpio-(3|135) ' /sys/kernel/debug/gpio"

echo
echo "=== try an i2c write to fan53870 0x35 (error type tells us why) ==="
$SSH "i2cget -y 12 0x35 0x00 2>&1; echo rc=\$?"
echo "--- and the known-good 0x66 for comparison ---"
$SSH "i2cget -y 12 0x66 0x00 2>&1; echo rc=\$?"

echo
echo "=== any 0x35 / fan messages ==="
$SSH "dmesg | grep -iE '0x35|fan|onsemi' | tail -10"
} >> "$OUT" 2>&1
echo "CAMGPIO_DONE" >> "$OUT"