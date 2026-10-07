#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
K=/tmp/${K50_KEY}
H=root@${K50_HOST}
scp -q -i "$K" -o StrictHostKeyChecking=no ${K50_REPO}/scripts/port2_rx70.py "$H:/root/"
ssh -i "$K" -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$H" 'date; echo "=== cam_go_v6 ==="; sh /root/cam_go_v6.sh 2>&1 | tail -14; echo "=== fp_fast3 ==="; /root/fp_fast3 2>&1 | tail -12; echo "=== port2_rx70 ==="; python3 /root/port2_rx70.py'
