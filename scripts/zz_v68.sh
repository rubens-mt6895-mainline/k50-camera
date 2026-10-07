#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
SCP="scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no"
$SCP ${K50_REPO}/scripts/port2_rx68.py root@${K50_HOST}:/root/ >/dev/null 2>&1

echo "===== cam_go_v6 + fp_fast3 ====="
$H 'sh /root/cam_go_v6.sh >/dev/null 2>&1; cd /root && ./fp_fast3 2>&1 | sed -n "1,2p;8,12p"'
echo "===== RX68: LANE_EN bit1 fix + PKT watch ====="
$H 'cd /root && python3 port2_rx68.py 2>&1'
