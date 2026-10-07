#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"

echo "===== i2c adapters still present? ====="
$H 'i2cdetect -l 2>&1; echo "---"; ls -l /dev/i2c-* 2>&1'
echo
echo "===== i2c-10 / i2c-11 identity + driver ====="
$H 'for b in 9 10 11; do echo "i2c-$b name=$(cat /sys/bus/i2c/devices/i2c-$b/name 2>&1)"; readlink -f /sys/bus/i2c/devices/i2c-$b 2>&1; done'
echo
echo "===== retry sensor + pmic ====="
$H 'echo "bus10: $(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1)"; echo "bus11: $(i2ctransfer -f -y 11 w2@0x35 0x03 r1 2>&1)"; echo "bus8: $(i2ctransfer -f -y 8 w2@0x10 0x00 0x16 r1 2>&1)"'
echo
echo "===== dmesg tail: i2c / pmic / faults ====="
$H 'dmesg | tail -30'
echo
echo "===== dmesg grep i2c/mt65xx ====="
$H 'dmesg | grep -iE "i2c|mt65xx|tx timeout|arbitration|lost" | tail -25'
echo
echo "===== gpio 149/20/159/158/164/155/152 + MODE152 ====="
$H 'g=/root/gpiotoolG; for p in 149 20 159 158 164 155; do echo "gpio$p dir=$(cat /sys/class/gpio/gpio$p/direction 2>/dev/null) val=$(cat /sys/class/gpio/gpio$p/value 2>/dev/null)"; done; busybox devmem 0x10005430 32; busybox devmem 0x10005420 32'
echo
echo "===== sensor reg 0x0100 (is it streaming now?) ====="
$H 'i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1'
