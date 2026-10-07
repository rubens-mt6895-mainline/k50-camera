#!/bin/sh
# zz_push.sh <name.sh> - WSL 侧：推送并执行设备侧脚本
H=${K50_REPO}
S=$1
if [ -z "$S" ]; then echo "usage: zz_push.sh <name.sh>"; exit 2; fi
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$H/$S" root@${K50_HOST}:/root/"$S" >/dev/null 2>&1
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} "sh /root/$S" 2>&1
