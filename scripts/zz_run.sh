#!/bin/bash
# zz_run.sh <remote-script-on-device>  - push nothing, just run a script already in /root on the device.
# Invoke: wsl -- bash -lc "bash ${K50_REPO}/scripts/zz_run.sh zz_v80.sh"
S="$1"
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
timeout 300 ssh $OPTS root@${K50_HOST} "sh /root/$S"
echo "ssh rc=$?"
