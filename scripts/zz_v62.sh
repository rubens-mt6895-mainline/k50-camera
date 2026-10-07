#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
SCP="scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no"
$SCP ${K50_REPO}/scripts/port2_rx62.py root@${K50_HOST}:/root/ >/dev/null 2>&1

echo "===== sensor table + stream (fp_fast3) ====="
$H 'cd /root && ./fp_fast3 2>&1 | head -3'
echo "===== all-6 DPHY enable + FSM ====="
$H 'cd /root && python3 port2_rx62.py 2>&1'
