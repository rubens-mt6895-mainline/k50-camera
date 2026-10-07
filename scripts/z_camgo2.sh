#!/bin/bash
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH 'sh /root/cam_go.sh 2>&1; echo "rc=$?"' > ${K50_REPO}/out/camgo_full.log 2>/dev/null
echo DONE
