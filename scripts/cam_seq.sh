#!/bin/bash
# cam_seq.sh - camera power-up sequence for IMX582 (rubens main cam)
# rails -> fan53870 LDOs -> MCLK pinmux -> RST pulse
G=/root/gpiotoolG

# 1. power rails (already-high is fine, idempotent)
for pin in 158 149 20 159 164; do
  $G $pin 1 >/dev/null 2>&1
  echo "gpio$pin = $($G $pin get 2>/dev/null)"
done

# 2. fan53870 camera PMIC (i2c-11 @ 0x35): enable all 7 LDOs
i2cset -f -y 11 0x35 0x03 0x7F 2>&1
echo "fan53870 ENABLE = $(i2cget -f -y 11 0x35 0x03 2>&1)"

# 3. MCLK: GPIO152 -> func1 (CMMCLK2)
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
echo "GPIO152 func1" > $P 2>&1 && echo "mclk pinmux set"

# 4. RST: GPIO155 low 50ms -> high
$G 155 0 >/dev/null 2>&1
sleep 0.05
$G 155 1 >/dev/null 2>&1
echo "gpio155 rst = $($G 155 get 2>/dev/null)"
sleep 0.01
echo "cam_seq done"
