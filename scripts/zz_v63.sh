#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
SCP="scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no"
$SCP ${K50_REPO}/scripts/port2_rx63.py root@${K50_HOST}:/root/ >/dev/null 2>&1

echo "===== cam_go_v6 (rails+RST) ====="
$H 'sh /root/cam_go_v6.sh 2>&1 | tail -3'
echo "===== fp_fast3 (236-reg table + stream) ====="
$H 'cd /root && ./fp_fast3 2>&1 | tail -6'
echo "===== FULL analog bring-up + DPHY RX + FSM ====="
$H 'cd /root && python3 port2_rx63.py 2>&1'
