#!/bin/bash
# zz_app_run.sh <device-script-name> - push + run one device-side script over ssh.
# usage: bash zz_app_run.sh zz_cheese_install.sh
S=${1:-zz_app_install2.sh}
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}
sed -i 's/\r$//' "${K50_REPO}/scripts/$S"
timeout 60 scp $OPTS "${K50_REPO}/scripts/$S" "$H:/root/$S"
echo "scp $S rc=$?"
timeout 900 ssh $OPTS $H "sh /root/$S" 2>&1 | grep -v "Permanently added"
echo "ssh rc=$?"
