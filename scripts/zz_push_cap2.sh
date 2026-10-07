#!/bin/sh
# zz_push_cap2.sh - push the routing-capable cam_cap.ko + zz_cap2.sh, run once.
H=${K50_REPO}
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
K="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
scp $K "$H/out/camcap_0b8dd2e/cam_cap.ko" root@${K50_HOST}:/root/cam_cap.ko >/dev/null 2>&1 || echo "scp FAILED ko"
scp $K "$H/zz_cap2.sh" root@${K50_HOST}:/root/zz_cap2.sh >/dev/null 2>&1 || echo "scp FAILED sh"
ssh $K root@${K50_HOST} "nice -n 19 sh /root/zz_cap2.sh" 2>&1
