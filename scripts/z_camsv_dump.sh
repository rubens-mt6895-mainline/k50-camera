#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'cat > /root/rdmem.py' < ${K50_REPO}/scripts/rdmem.py
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'timeout 8 python3 /root/rdmem.py; echo RC=$?' 2>&1
