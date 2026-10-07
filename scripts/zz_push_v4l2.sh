#!/bin/bash
# Push the V4L2 .ko stack to the K50 and try to load it.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}; chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
H=root@${K50_HOST}

timeout 30 ssh $OPTS $H "mkdir -p /root/v4l2" >/dev/null 2>&1
echo "--- scp ---"
timeout 240 scp $OPTS ${K50_REPO}/out/v4l2/*.ko "$H:/root/v4l2/" 2>&1 | grep -v Permanently || true
timeout 60 scp $OPTS ${K50_REPO}/scripts/v4l2_load.sh "$H:/root/v4l2_load.sh" 2>&1 | grep -v Permanently || true
echo "--- remote ls ---"
timeout 30 ssh $OPTS $H "ls -l /root/v4l2/"
echo "--- run ---"
timeout 300 ssh $OPTS $H "sh /root/v4l2_load.sh" 2>&1 | grep -v Permanently
echo "ssh rc=$?"
