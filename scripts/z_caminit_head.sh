#!/bin/bash
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH 'head -60 /root/cam_init.sh; echo "==== TAIL ===="; tail -40 /root/cam_init.sh' > ${K50_REPO}/out/caminit_head.log 2>&1
echo DONE
