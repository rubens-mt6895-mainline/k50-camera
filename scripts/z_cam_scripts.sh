#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'echo "=== cam_load.sh ==="; cat /root/cam_load.sh; echo; echo "=== cam_go.sh ==="; cat /root/cam_go.sh' 2>&1
