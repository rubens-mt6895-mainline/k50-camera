#!/bin/bash
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH 'cat > /root/seninf_diff.py' < ${K50_REPO}/scripts/seninf_diff.py
$SSH 'python3 /root/seninf_diff.py > /root/seninf_diff.log 2>&1; cat /root/seninf_diff.log' > ${K50_REPO}/out/seninf_diff.log 2>/dev/null
echo DONE
