#!/bin/sh
# zz_v77.sh - 供电确认 + IMX582 init/preview/stream-on + CSI2 包计数采样
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select

echo "=== zz_v77: IMX582 stream bring-up ==="
date

echo "--- 1. fan53870 power (idempotent) ---"
i2ctransfer -f -y 11 w2@0x35 0x09 0xbf 2>&1
i2ctransfer -f -y 11 w2@0x35 0x0a 0x36 2>&1
i2ctransfer -f -y 11 w2@0x35 0x03 0x60 2>&1
echo "  0x03=$(i2ctransfer -f -y 11 w1@0x35 0x03 r1 2>&1) 0x09=$(i2ctransfer -f -y 11 w1@0x35 0x09 r1 2>&1) 0x0a=$(i2ctransfer -f -y 11 w1@0x35 0x0a r1 2>&1)"

echo "--- 2. rails high ---"
for pin in 149 20 159 158 164; do $G $pin 1 >/dev/null 2>&1; done

echo "--- 3. MCLK pinmux + clk ---"
echo "GPIO152 func1" > $P 2>/dev/null
echo "  MODE152=$(busybox devmem 0x10005430 32 2>&1)"
grep -E "camtg3_ck|camtg3_sel|cam_m_seninf" /sys/kernel/debug/clk/clk_summary 2>/dev/null | head -4

echo "--- 4. reset pulse ---"
$G 155 0 >/dev/null 2>&1
sleep 0.05
$G 155 1 >/dev/null 2>&1
sleep 0.05

echo "--- 5. sensor id ---"
echo "  ID16=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1) ID17=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>&1)"

echo "--- 6. init + preview + stream on ---"
python3 /root/imx582_bring.py 2>&1

echo "--- 7. sampling CSI2 PKT / IRQ / DPHY lane FSM (20 x 0.25s) ---"
i=0
while [ $i -lt 20 ]; do
  printf "  [%02d] PKT=%s IRQ=%s ckFSM=%s datFSM=%s\n" $i \
    "$(busybox devmem 0x1a014adc 32 2>&1)" \
    "$(busybox devmem 0x1a014ac8 32 2>&1)" \
    "$(busybox devmem 0x11c86030 32 2>&1)" \
    "$(busybox devmem 0x11c86034 32 2>&1)"
  i=$((i+1))
  sleep 0.25
done
echo "=== done ==="
