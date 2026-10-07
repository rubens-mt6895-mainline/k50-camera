#!/bin/bash
# zz_check.sh - WSL-side liveness + camera-state probe (single ssh, niced).
# Invoke: wsl -- bash -lc "bash ${K50_REPO}/scripts/zz_check.sh"
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
echo "=== scp remote probe ==="
timeout 40 scp $OPTS ${K50_REPO}/scripts/zz_check_remote.sh root@${K50_HOST}:/root/zz_check_remote.sh
echo "scp rc=$?"
echo "=== remote probe ==="
timeout 90 ssh $OPTS root@${K50_HOST} "nice -n 19 sh /root/zz_check_remote.sh"
echo "ssh rc=$?"
