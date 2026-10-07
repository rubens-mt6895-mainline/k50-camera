#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
echo "===== re-run cam_go_v6.sh (rails + RST pulse) ====="
$H 'sh /root/cam_go_v6.sh 2>&1'
echo
echo "===== after: sensor bus 10 + fan53870 bus 11 ====="
$H 'echo "bus10 id: $(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1)"; echo "bus10 0100: $(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1)"; echo "bus11 0x35: $(i2ctransfer -f -y 11 w2@0x35 0x03 r1 2>&1)"; echo "bus9 0x10: $(i2ctransfer -f -y 9 w2@0x10 0x00 0x16 r1 2>&1)"'
echo
echo "===== i2cdetect on camera buses 8 9 10 11 ====="
$H 'for b in 8 9 10 11; do echo "--- bus $b ---"; i2cdetect -y -r $b 2>&1 | head -12; done'
echo
echo "===== gpio exports back? ====="
$H 'for p in 149 20 159 158 164 155; do echo "gpio$p: $(cat /sys/class/gpio/gpio$p/value 2>&1)"; done'
echo
echo "===== CAM rails via pinctrl/regulator ====="
$H 'grep -iE "vcam|cam|fan" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | head -20'
