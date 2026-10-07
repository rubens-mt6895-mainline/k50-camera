#!/bin/bash
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}; chmod 600 /tmp/${K50_KEY}
O="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
H=root@${K50_HOST}
D=${K50_REPO}/frames
mkdir -p $D
for f in tpg_on.bin tpg_off.bin; do
  timeout 180 scp $O $H:/tmp/$f $D/$f >/dev/null 2>&1 && ls -l $D/$f
done
md5sum $D/tpg_on.bin $D/tpg_off.bin
