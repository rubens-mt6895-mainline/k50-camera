#!/bin/bash
# zz_cma.sh - push zz_cma_remote.sh and run it once.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
timeout 60 scp $OPTS ${K50_REPO}/scripts/zz_cma_remote.sh root@${K50_HOST}:/root/zz_cma_remote.sh
echo "scp rc=$?"
timeout 90 ssh $OPTS root@${K50_HOST} "nice -n 19 sh /root/zz_cma_remote.sh"
echo "ssh rc=$?"
