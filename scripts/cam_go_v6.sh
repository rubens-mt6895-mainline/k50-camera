#!/bin/sh
# cam_go_v6.sh - K50 主摄 IMX582 复活序列（2026-10-05，9.4f 权威配方集成版）
# 依据 project_memory §9.4f（2026-10-02 原理图+原厂 fdt 双实证）：
#   电源绑定 avdd1=vcam_ldo(GPIO158 1.2V) / dovdd=fan53870-L7(1.8V) / afvdd=fan53870-L6(2.8V)
#   fan53870: L6(0x09)=0x2C(2.8V afvdd)、L7(0x0a)=0x18(1.8V dovdd)、PWRON=0x7f（先 VOUT 后 PWRON，禁 0xff）
#   GPIO 使能脚（必须拉高，重启后掉电）：GPIO149=avdd 2.9V / GPIO20=avdd2 1.8V / GPIO159=dvdd 1.1V /
#                                      GPIO158=vcam_ldo 1.2V / GPIO164=rt5133en / GPIO155=rst
#   顺序: avdd(149)->avdd2(20)->dvdd(159)->vcam_ldo(158)->dovdd/afvdd(fan53870)->rst高(155)->mclk(152)稳定
#   MCLK=GPIO152(CMMCLK2) func1 + camtg3_sel 24MHz（时钟树与引脚独立映射，别动 GPIO162）
#   模块重载：rails 最后（RST 脉冲由 cam_rails 在 MCLK 稳定后打，sensor PLL 才 lock）
G=/root/gpiotoolG
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
BUS=11; ADDR=0x35   # fan53870 (dtsi &i2c9 -> bus11)

echo "=== cam_go_v6: IMX582 复活序列 ==="

# 0. 确保 gpiotoolG 存在
if [ ! -x "$G" ]; then echo "FATAL: $G missing"; exit 1; fi

# 1. GPIO rails 上电（幂等，重启后必做）
for pin in 149 20 159 158 164; do
  $G $pin 1 >/dev/null 2>&1
  echo "gpio$pin = $($G $pin get 2>/dev/null)"
done
sleep 0.2

# 2. fan53870：先 VOUT 后 PWRON（i2ctransfer，i2cset 在此内核 Write failed 不可用）
i2ctransfer -f -y $BUS w2@$ADDR 0x0a 0x18 2>&1   # L7 dovdd 1.8V  (0x18=1.5+(0x18-16)*8mV=1.804V)
i2ctransfer -f -y $BUS w2@$ADDR 0x09 0x2c 2>&1   # L6 afvdd 2.8V  (0x2c=1.5+(0x2c-16)*8mV=2.804V)
i2ctransfer -f -y $BUS w2@$ADDR 0x03 0x7f 2>&1   # PWRON 全 LDO（0x7f 安全，禁 0xff -> OCP 锁存）
sleep 0.3
echo "fan53870: 0x03=$(i2cget -f -y $BUS $ADDR 0x03 2>&1) 0x09=$(i2cget -f -y $BUS $ADDR 0x09 2>&1) 0x0a=$(i2cget -f -y $BUS $ADDR 0x0a 2>&1)"

# 3. 模块栈重载（rails 最后 -> RST 脉冲在 MCLK 稳定后打）
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

# 4. MCLK pinmux（GPIO152 -> CMMCLK2 func1）+ 时钟树确认
echo "GPIO152 func1" > $P 2>/dev/null
echo "MODE152=$(busybox devmem 0x10005430 32 2>/dev/null)"
grep -E "camtg3_sel|camtg3_ck" /sys/kernel/debug/clk/clk_summary 2>/dev/null | head -4

# 5. RST：GPIO155 低 50ms -> 高（rails 重载后 MCLK 已稳定）
$G 155 0 >/dev/null 2>&1
sleep 0.05
$G 155 1 >/dev/null 2>&1
sleep 0.01
echo "gpio155 rst = $($G 155 get 2>/dev/null)"

# 6. IMX582 存活检查
ID16=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>/dev/null)
ID17=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>/dev/null)
echo "ID16: $ID16  ID17: $ID17"
if [ "$ID16" = "0x05" ] && [ "$ID17" = "0x82" ]; then
  echo "IMX582 ALIVE"
else
  echo "IMX582 DEAD (id=$ID16/$ID17)"
fi

# 7. 回读 sensor 关键寄存器（PLL lock / 模式）：i2ctransfer 16-bit 地址为字节对
for pair in "0x01 0x00:0x0100" "0x01 0x14:0x0114" "0x01 0x15:0x0115" "0x03 0x07:0x0307"; do
  addr="${pair%%:*}"; reg="${pair##*:}"
  v=$(i2ctransfer -f -y 10 w2@0x10 $addr r1 2>/dev/null)
  echo "reg $reg = $v"
done
echo "=== cam_go_v6 done ==="
