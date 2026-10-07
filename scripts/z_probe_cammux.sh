#!/bin/bash
SCP="scp -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY}"
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SCP ${K50_REPO}/scripts/probe_cammux.py root@${K50_HOST}:/root/probe_cammux.py
$SSH 'python3 /root/probe_cammux.py' > ${K50_REPO}/out/probe_cammux.log 2>&1
echo DONE
