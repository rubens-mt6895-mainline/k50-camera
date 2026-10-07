#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
R() { $H "$1"; }

echo "===== lsmod / stack ====="
R 'lsmod | head -12; uptime'

echo
echo "===== sensor regs BEFORE ====="
R 'for a in "0x01 0x00" "0x01 0x14" "0x01 0x15" "0x01 0x12" "0x01 0x13" "0x03 0x07" "0x00 0x16" "0x00 0x17"; do v=$(i2ctransfer -f -y 10 w2@0x10 $a r1 2>&1); echo "$a = $v"; done'

echo
echo "===== WRITE 0x0100 = 0x01 (stream on) then read back ====="
R 'i2ctransfer -f -y 10 w3@0x10 0x01 0x00 0x01 2>&1; sleep 0.2; echo "readback 0x0100 = $(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1)"'
R 'sleep 0.5; echo "readback again 0x0100 = $(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1)"'

echo
echo "===== write 0x0100=0x00 (standby) then back 0x01, read both ====="
R 'i2ctransfer -f -y 10 w3@0x10 0x01 0x00 0x00 2>&1; sleep 0.1; echo "after w0: $(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1)"; i2ctransfer -f -y 10 w3@0x10 0x01 0x00 0x01 2>&1; sleep 0.3; echo "after w1: $(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1)"'

echo
echo "===== CSI2 pkt cnt / DPHY FSM / seninf top (2 samples 1s apart) ====="
R 'for i in 1 2; do echo "--- sample $i ---"; busybox devmem 0x1a014adc 32; busybox devmem 0x11c8a030 32; busybox devmem 0x11c8a034 32; busybox devmem 0x1a014a00 32; busybox devmem 0x1a010010 32; sleep 1; done'

echo
echo "===== imx582 0x0114 lane mode / 0x0301 / 0x0303 / 0x0305 ====="
R 'for a in "0x01 0x14" "0x03 0x01" "0x03 0x03" "0x03 0x05" "0x03 0x11" "0x03 0x13" "0x03 0x15" "0x03 0x17"; do v=$(i2ctransfer -f -y 10 w2@0x10 $a r1 2>&1); echo "$a = $v"; done'
