#!/bin/bash
# zz_push9.sh - push and run zz_cap9.sh.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}
timeout 90 scp $OPTS ${K50_REPO}/scripts/zz_cap9.sh "$H:/root/zz_cap9.sh" >/dev/null 2>&1
echo "scp sh rc=$?"
timeout 420 ssh $OPTS $H "sh /root/zz_cap9.sh" 2>&1 | grep -v "Permanently added"
echo "ssh rc=$?"
