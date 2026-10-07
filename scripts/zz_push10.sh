#!/bin/bash
# zz_push10.sh - run zz_cap10.sh and pull the frame back.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}
timeout 90 scp $OPTS ${K50_REPO}/scripts/zz_cap10.sh "$H:/root/zz_cap10.sh" >/dev/null 2>&1
echo "scp sh rc=$?"
timeout 300 ssh $OPTS $H "sh /root/zz_cap10.sh" 2>&1 | grep -v "Permanently added"
echo "ssh rc=$?"
timeout 300 scp $OPTS "$H:/root/frame10.bin" ${K50_REPO}/frames/frame10.bin >/dev/null 2>&1
echo "scp frame rc=$?"
ls -l ${K50_REPO}/frames/frame10.bin 2>/dev/null
