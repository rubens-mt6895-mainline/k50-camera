#!/bin/sh
# cam_go.sh v5 - K50 主摄 IMX582 复活序列（2026-10-01 原厂 dtsi 校正版）
# 主摄 sensor0 供电（rubens_mt6895_camera_v4l2.dtsi L756）：
#   dovdd=fan53870_l7(1.8V) / afvdd=fan53870_l6(2.8V) / avdd1=vcam_ldo(GPIO158 1.2V) / dvdd=GPIO159 轨
# fan53870（datasheet 公式 LDO3-7: 1.5+(d-16)*8mV）：
#   L7 = 0x36 -> 1.804V (reg 0x0a)  ⚠️ 严禁 2.8V（1.8V 轨，过压疑损 MIPI TX）
#   L6 = 0xb3 -> 2.804V (reg 0x09)
#   ENABLE 0x03 = L6|L7 = 0x60  (禁止写 0xff -> OCP 锁存!)
# dvdd/avdd 由 GPIO 轨提供（cam_rails.ko）。顺序: 先 VOUT 后 PWRON。

echo "=== fan53870 (bus11 0x35) main-cam mapping ==="
i2ctransfer -f -y 11 w2@0x35 0x0a 0x36 2>/dev/null   # L7 dovdd 1.804V
i2ctransfer -f -y 11 w2@0x35 0x09 0xb3 2>/dev/null   # L6 afvdd 2.804V
i2ctransfer -f -y 11 w2@0x35 0x03 0x60 2>/dev/null   # EN L6+L7
sleep 0.3
for r in 03 09 0a; do
  v=$(i2ctransfer -f -y 11 w1@0x35 0x$r r1 2>/dev/null)
  echo "reg 0x$r = $v"
done

# 模块栈（rails 最后 -> RST 脉冲在 MCLK 稳定后打）
for m in cam_clk3 cam_clk cam_clk2 cam_rails cam_genpd cam_ovl; do
  rmmod $m 2>/dev/null
done
sleep 0.5
for m in cam_ovl cam_genpd cam_clk2 cam_clk cam_clk3 cam_rails; do
  if ! lsmod | grep -q "^$m "; then
    insmod /root/$m.ko 2>/dev/null
  fi
  sleep 0.5
done

# MCLK pinmux（GPIO152 -> CMMCLK2 func1）
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
echo "GPIO152 func1" > $P 2>/dev/null
echo "MODE152=$(busybox devmem 0x10005430 32 2>/dev/null)"

E3=$(cat /sys/kernel/debug/clk/camtg3_ck/clk_enable_count 2>/dev/null)
echo "camtg3_ck enable=$E3"

ID16=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>/dev/null)
ID17=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>/dev/null)
echo "ID16: $ID16  ID17: $ID17"
if [ "$ID16" = "0x05" ] && [ "$ID17" = "0x82" ]; then
  echo "IMX582 ALIVE"
else
  echo "IMX582 DEAD (id=$ID16/$ID17)"
fi
