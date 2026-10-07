#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
SCP="scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no"
$SCP ${K50_REPO}/scripts/port2_rx61.py root@${K50_HOST}:/root/port2_rx61.py >/dev/null 2>&1

echo "===== 1. cam_go_v6 (rails + RST + ID) ====="
$H 'sh /root/cam_go_v6.sh 2>&1 | tail -4'
echo "===== 2. fp_fast3: fast 236-reg table + stream ====="
$H 'cd /root && ./fp_fast3 2>&1 | head -14'
echo "===== 3. DPHY RX + SENINF digital (both PHY candidates) + FSM/PKT ====="
$H 'cd /root && python3 port2_rx61.py 2>&1'
