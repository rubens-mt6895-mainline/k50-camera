#!/bin/bash
# zz_push_cap4.sh - push cam_cap.ko + zz_cap4.sh and run it once.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}
timeout 60 scp $OPTS ${K50_REPO}/scripts/zz_cap4.sh $H:/root/zz_cap4.sh; echo "scp4 rc=$?"
timeout 60 scp $OPTS ${K50_REPO}/out/camcap_0b8dd2e/cam_cap.ko $H:/root/cam_cap.ko; echo "scpko rc=$?"
timeout 60 ssh $OPTS $H "ls -l /root/cam_cap.ko /root/zz_cap4.sh"
timeout 240 ssh $OPTS $H "sh /root/zz_cap4.sh"
echo "ssh rc=$?"
