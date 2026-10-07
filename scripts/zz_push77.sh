#!/bin/sh
# zz_push77.sh - WSL 侧：推送 imx582_bring.py + zz_v77.sh 并执行
H=${K50_REPO}
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$H/imx582_bring.py" root@${K50_HOST}:/root/imx582_bring.py >/dev/null 2>&1
scp -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$H/zz_v77.sh" root@${K50_HOST}:/root/zz_v77.sh >/dev/null 2>&1
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} 'sh /root/zz_v77.sh' 2>&1
