#!/bin/bash
# zz_pushko.sh - push the freshly built cam_cap.ko and zz_cap5.sh, then run it.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}
KO=${K50_REPO}/out/camcap_0b8dd2e/cam_cap.ko
echo "=== ko to push ==="
ls -l "$KO"
timeout 60 scp $OPTS "$KO" "$H:/root/cam_cap.ko" >/dev/null 2>&1
echo "scp ko rc=$?"
timeout 60 scp $OPTS ${K50_REPO}/scripts/zz_cap5.sh "$H:/root/zz_cap5.sh" >/dev/null 2>&1
echo "scp sh rc=$?"
echo "=== run ==="
timeout 240 ssh $OPTS $H "sh /root/zz_cap5.sh" 2>&1 | grep -v "Permanently added"
echo "ssh rc=$?"
