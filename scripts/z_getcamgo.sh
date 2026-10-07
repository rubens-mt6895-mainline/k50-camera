#!/bin/bash
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH 'cat /root/cam_go.sh' > ${K50_REPO}/out/dev_cam_go.sh 2>/dev/null
$SSH 'cat /root/cam_init.sh | head -20' > ${K50_REPO}/out/dev_cam_init_head.sh 2>/dev/null
echo DONE
