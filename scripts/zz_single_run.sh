#!/bin/bash
# zz_single_run.sh - push the freshly built cam_cap.ko + zz_single.sh and run it.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}
timeout 90 scp $OPTS ${K50_REPO}/out/camcap_0b8dd2e/cam_cap.ko "$H:/root/cam_cap.ko"
echo "scp ko rc=$?"
timeout 60 scp $OPTS ${K50_REPO}/scripts/zz_single.sh "$H:/root/zz_single.sh"
echo "scp sh rc=$?"
timeout 300 ssh $OPTS $H "sh /root/zz_single.sh" 2>&1 | grep -v "Permanently added"
echo "ssh rc=$?"
