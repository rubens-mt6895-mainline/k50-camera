#!/bin/sh
# zz_push75.sh - WSL 侧：推送并执行 zz_v75.sh
H=${K50_REPO}
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$H/zz_v75.sh" root@${K50_HOST}:/root/zz_v75.sh
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} 'sh /root/zz_v75.sh' 2>&1
