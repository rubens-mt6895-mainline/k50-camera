#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'cat > /root/cam_init.sh' < ${K50_REPO}/scripts/cam_init.sh
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'sh /root/cam_go.sh > /root/full1.log 2>&1; sh /root/cam_init.sh > /root/full2.log 2>&1; python3 /root/sv37.py > /root/full3.log 2>&1; cat /root/full1.log; echo "=== init ==="; cat /root/full2.log; echo "=== frame ==="; cat /root/full3.log' > ${K50_REPO}/out/full_test.log 2>/dev/null
echo DONE
