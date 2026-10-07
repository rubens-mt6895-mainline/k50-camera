#!/bin/bash
# WSL-side helper: push one device-side script from ${K50_REPO}\scripts and run it.
# usage: zz_pr.sh <name.sh>
S=${1:?usage: zz_pr.sh name.sh}
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}; chmod 600 /tmp/${K50_KEY}
O="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
H=root@${K50_HOST}
tr -d '\r' < ${K50_REPO}/scripts/$S > /tmp/$S
timeout 120 scp $O /tmp/$S $H:/root/$S || { echo "SCP FAILED"; exit 1; }
timeout 400 ssh $O $H "chmod +x /root/$S; nice -n 19 sh /root/$S" 2>&1
echo "--- exit $? ---"
