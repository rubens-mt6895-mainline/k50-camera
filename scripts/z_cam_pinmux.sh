#!/bin/sh
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
echo "MARKER_START"
echo "=== pinmux-select ==="
ls -la $P/pinmux-select 2>&1
echo "=== try A: GPIO152 func1 ==="
echo "GPIO152 func1" > $P/pinmux-select 2>&1; echo "A rc=$?"
grep "pin 152" $P/pinmux-pins
echo "=== try B: 152 func1 ==="
echo "152 func1" > $P/pinmux-select 2>&1; echo "B rc=$?"
grep "pin 152" $P/pinmux-pins
echo "=== try C: 152 1 ==="
echo "152 1" > $P/pinmux-select 2>&1; echo "C rc=$?"
grep "pin 152" $P/pinmux-pins
echo "=== clocks ==="
for c in camtg3_sel camtg3_ck cam_m_camtg_con; do
  n=$(find /sys/kernel/debug/clk -maxdepth 1 -name "*$c*" 2>/dev/null | head -1)
  echo "$c: en=$(cat $n/clk_enable_count 2>/dev/null) rate=$(cat $n/clk_rate 2>/dev/null)"
done
echo "=== sensor ==="
v=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1 | tr -d '\n')
echo "id16=$v"
echo "MARKER_END"
