#!/bin/sh
# zz_v75.sh - 主摄模块供电修复：FAN53870 LDO7(DOVDD)=1.804V / LDO6(AFVDD)=2.900V + 使能
# 依据 hyperos_workstate/regulator_summary.txt（HyperOS 相机工作态实测）：
#   fan53870-l7 use=1 1804mV -> 8-0010-dovdd   => reg 0x0A (LDO7_VOUT) = 0x36 (1.500+(54-16)*0.008=1.804)
#   fan53870-l6 use=1 2900mV -> 8-0010-afvdd   => reg 0x09 (LDO6_VOUT) = 0xBF (1.500+(191-16)*0.008=2.900)
#   reg 0x03 ENABLE: bit6=LDO7_EN, bit5=LDO6_EN  => 0x60
# 修复 cam_go_v6.sh 的两处算错：0x0a=0x18(实为1.564V) / 0x09=0x2c(实为2.724V) / 0x03=0x7f(全开)
G=/root/gpiotoolG
BUS=11; ADDR=0x35

echo "=== zz_v75: FAN53870 DOVDD/AFVDD bring-up ==="
date; uptime

echo "--- 0. before ---"
for r in 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x10 0x12 0x13; do
  printf "  reg %s = %s\n" "$r" "$(i2ctransfer -f -y $BUS w1@$ADDR $r r1 2>&1)"
done

echo "--- 1. program VOUT then ENABLE ---"
i2ctransfer -f -y $BUS w2@$ADDR 0x09 0xbf 2>&1   # LDO6_VOUT = 0xBF -> 2.900V (afvdd)
i2ctransfer -f -y $BUS w2@$ADDR 0x0a 0x36 2>&1   # LDO7_VOUT = 0x36 -> 1.804V (dovdd)
i2ctransfer -f -y $BUS w2@$ADDR 0x03 0x60 2>&1   # ENABLE bit6(LDO7) | bit5(LDO6)
sleep 0.3

echo "--- 2. after (0x16..0x1b = INT/STATUS, 0x1b bit6=CHIP_SUSD) ---"
for r in 0x03 0x09 0x0a 0x16 0x18 0x19 0x1a 0x1b; do
  printf "  reg %s = %s\n" "$r" "$(i2ctransfer -f -y $BUS w1@$ADDR $r r1 2>&1)"
done

echo "--- 3. GPIO rails ---"
for pin in 149 20 159 158 164; do
  $G $pin 1 >/dev/null 2>&1
  echo "  gpio$pin = $($G $pin get 2>/dev/null)"
done
sleep 0.1

echo "--- 4. sensor reset pulse (GPIO155) ---"
$G 155 0 >/dev/null 2>&1
sleep 0.05
$G 155 1 >/dev/null 2>&1
sleep 0.05
echo "  gpio155 = $($G 155 get 2>/dev/null)"

echo "--- 5. main camera bus (i2c-10 = 11d05000) ---"
i2cdetect -y -r 10
echo "  sensor 0x10 ID16 = $(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1)"
echo "  sensor 0x10 ID17 = $(i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>&1)"
echo "  af 0x0c reg0x02   = $(i2ctransfer -f -y 10 w1@0x0c 0x02 r1 2>&1)"
echo "  eeprom 0x51 reg0x00 = $(i2ctransfer -f -y 10 w1@0x51 0x00 r1 2>&1)"
echo "=== done ==="
