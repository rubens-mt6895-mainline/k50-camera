#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
R10() { $H "i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1"; }
echo "===== step0 baseline: bus10 map + fan53870 regs ====="
$H 'echo "--bus10 map--"; i2cdetect -y -r 10 2>&1 | sed -n "1,8p"'
$H 'echo "fan53870 0x03: $(i2ctransfer -f -y 11 w1@0x35 0x03 r1 2>&1)"; echo "fan53870 0x09: $(i2ctransfer -f -y 11 w1@0x35 0x09 r1 2>&1)"; echo "fan53870 0x0a: $(i2ctransfer -f -y 11 w1@0x35 0x0a r1 2>&1)"'
echo "sensor 0x0100 pre = $(R10)"
echo
echo "===== step1 WRITE 0x0100 = 0x01 (stream on) ====="
$H 'i2ctransfer -f -y 10 w3@0x10 0x01 0x00 0x01 2>&1; echo "write rc=$?"'
echo "immediate read 0x0100: $($H 'i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1')"
echo "after 200ms read   : $($H 'sleep 0.2; i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1')"
echo
echo "===== step2 who died on bus10? (0x10 sensor vs 0x0c / 0x51) ====="
echo "bus10 map after :"
$H 'i2cdetect -y -r 10 2>&1 | sed -n "1,8p"'
echo "other devices: $(i2ctransfer -f -y 10 w1@0x51 0x00 r1 2>&1)"
echo
echo "===== step3 did other buses die too? (bus8 eeprom, bus11 pmic) ====="
echo "bus8 map : "; $H 'i2cdetect -y -r 8 2>&1 | sed -n "5,8p"'
echo "bus11 map: "; $H 'i2cdetect -y -r 11 2>&1 | sed -n "3,8p"'
echo
echo "===== step4 recover by RELOADING cam_rails only (rst pulse) ====="
KO=$($H 'find / -name "cam_rails.ko" 2>/dev/null | head -1')
echo "cam_rails.ko at: $KO"
$H "rmmod cam_rails 2>&1; insmod $KO 2>&1; echo \"reload rc=\$?\"; sleep 0.3"
echo "sensor 0x0100 after rails reload = $($H 'i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1')"
echo
echo "===== step5 dmesg tail for cam_rails / i2c ====="
$H 'dmesg | tail -12'
