#!/bin/sh
# WSL-side: push port2_rx71.py + zz_v71.sh to the device and run it.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
sed -i 's/\r$//' ${K50_REPO}/scripts/zz_v71.sh ${K50_REPO}/scripts/port2_rx71.py
scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 \
    ${K50_REPO}/scripts/port2_rx71.py ${K50_REPO}/scripts/zz_v71.sh \
    root@${K50_HOST}:/root/ >/tmp/scp71.log 2>&1
echo "scp rc=$? "; cat /tmp/scp71.log
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    -o ServerAliveInterval=15 root@${K50_HOST} 'sh /root/zz_v71.sh' 2>&1
