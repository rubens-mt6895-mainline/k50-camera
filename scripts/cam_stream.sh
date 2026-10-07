#!/bin/sh
# cam_stream.sh - modules + pinmux + init + streaming (takeover version)
rmmod cam_rails 2>/dev/null
for m in cam_ovl cam_genpd cam_clk2 cam_clk cam_clk3 cam_rails; do
  insmod /tmp/$m.ko 2>/dev/null || insmod /root/$m.ko 2>/dev/null
  sleep 0.4
done
echo "modules loaded: $(lsmod | grep -c cam)"
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris/pinmux-select
echo "GPIO152 func1" > $P 2>/dev/null
echo "MODE152=$(busybox devmem 0x10005430 32)"
sh /root/cam_init.sh > /tmp/init.log 2>&1
echo "i2c-errors=$(grep -c Error /tmp/init.log)"
i2ctransfer -f -y 10 w3@0x10 0x03 0x50 0x01
i2ctransfer -f -y 10 w3@0x10 0x30 0x20 0x00
i2ctransfer -f -y 10 w3@0x10 0x01 0x00 0x01
sleep 0.3
echo "standby: $(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1)"
echo "framecnt: $(i2ctransfer -f -y 10 w2@0x10 0x00 0x05 r1 2>&1)"
sleep 0.15
echo "framecnt2: $(i2ctransfer -f -y 10 w2@0x10 0x00 0x05 r1 2>&1)"
