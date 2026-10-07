#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
K=${WINHOME}/.ssh/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
SCP="scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no"

echo "===== deploy fp_fast3 source + check binary ====="
$SCP ${K50_REPO}/src/fp_fast3.c root@${K50_HOST}:/root/fp_fast3.c 2>&1 | tail -2
$H 'test -x /root/fp_fast3 || gcc -O2 -o /root/fp_fast3 /root/fp_fast3.c; ls -l /root/fp_fast3'
echo
echo "===== GPIO bank4 raw regs BEFORE (0x10005210 DIN /5310 DIR /5110 DO /5710 DOSET /543c mode158-159) ====="
$H 'for a in 0x10005210 0x10005310 0x10005110 0x10005710 0x1000543c; do printf "%s = " $a; busybox devmem $a; done'
echo
echo "===== cam_go_v6 (cam_rails drives rails + RST) ====="
$H 'sh /root/cam_go_v6.sh 2>&1 | tail -6'
echo
echo "===== GPIO bank4 AFTER cam_go_v6 (DIN bits 27=155 30=158 31=159) ====="
$H 'd=$(busybox devmem 0x10005210); echo "DIN=$d"; p=$(busybox devmem 0x10005310); echo "DIR=$p"; q=$(busybox devmem 0x10005110); echo "DO=$q"'
echo
echo "===== dmesg cam_rails rail levels ====="
$H 'dmesg | grep cam_rails | tail -14'
echo
echo "===== RUN fp_fast3 (236-reg table + stream) + FSM/PKT ====="
$H 'cd /root && ./fp_fast3 2>&1 | tail -45'
echo
echo "===== post: FSM D2=0x11C86000 / PKT ====="
$H 'for a in 0x11C86030 0x11C86034 0x11C86038 0x1A014ADC 0x1A014A00 0x11C86000 0x11C85000; do printf "%s = " $a; busybox devmem $a; done'
