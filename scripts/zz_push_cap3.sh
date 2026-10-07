#!/bin/bash
# zz_push_cap3.sh - push the CMA-based cam_cap.ko + zz_cap3.sh, run once.
# Invoke: wsl -- bash -lc "bash ${K50_REPO}/scripts/zz_push_cap3.sh"
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
timeout 60 scp $OPTS ${K50_REPO}/out/camcap_0b8dd2e/cam_cap.ko root@${K50_HOST}:/root/cam_cap.ko
echo "scp ko rc=$?"
timeout 60 scp $OPTS ${K50_REPO}/scripts/zz_cap3.sh root@${K50_HOST}:/root/zz_cap3.sh
echo "scp sh rc=$?"
timeout 120 ssh $OPTS root@${K50_HOST} "nice -n 19 sh /root/zz_cap3.sh"
echo "ssh rc=$?"
