#!/bin/bash
# zz_pushrun.sh <name>.sh  - push ${K50_REPO}/<name> to /root and run it.
# Invoke: wsl -- bash -lc "bash ${K50_REPO}/scripts/zz_pushrun.sh zz_iommu_probe.sh"
S="$1"
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}
timeout 60 scp $OPTS "${K50_REPO}/scripts/$S" "$H:/root/$S" >/dev/null 2>&1
echo "scp rc=$?"
timeout 300 ssh $OPTS $H "sh /root/$S" 2>&1 | grep -v "Permanently added"
echo "ssh rc=$?"
