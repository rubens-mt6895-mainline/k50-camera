#!/bin/sh
# zz_push80.sh - WSL side: push the v80 bring-up + its python deps, then run it once.
# Serialized by design: one scp batch, one ssh session, no background loops.
H=${K50_REPO}
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
K="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
for f in port2_rx71.py imx582_bring.py zz_v80.sh; do
  scp $K "$H/$f" root@${K50_HOST}:/root/"$f" >/dev/null 2>&1 || echo "scp FAILED: $f"
done
ssh $K root@${K50_HOST} "nice -n 19 sh /root/zz_v80.sh" 2>&1
