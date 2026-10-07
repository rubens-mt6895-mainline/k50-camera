#!/bin/bash
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH 'bash /root/cam_go.sh 2>&1 | tail -6' > ${K50_REPO}/out/camgo_retry.log 2>&1
echo DONE
