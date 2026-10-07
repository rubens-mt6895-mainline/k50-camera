#!/bin/bash
# zz_shot_remote.sh -- WSL SIDE. Push zz_shot.sh to the K50, run it, pull the frame back.
# usage: zz_shot_remote.sh <tag> [dgain_hex]
TAG=${1:-shot}
DG=${2:-0400}
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} && chmod 600 /tmp/${K50_KEY}
O="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
H=root@${K50_HOST}
tr -d '\r' < ${K50_REPO}/scripts/zz_shot.sh > /tmp/zz_shot.sh
scp -q $O /tmp/zz_shot.sh $H:/root/zz_shot.sh || { echo "SCP FAILED"; exit 1; }
ssh $O $H "chmod +x /root/zz_shot.sh; nice -n 19 sh /root/zz_shot.sh $TAG $DG" 2>&1
scp -q $O $H:/tmp/$TAG.bin ${K50_REPO}/frames/$TAG.bin || { echo "PULL FAILED"; exit 1; }
echo "pulled frames/$TAG.bin"
