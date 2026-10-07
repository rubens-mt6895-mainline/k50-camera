#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'echo ALIVE; uptime; echo ===; ls /root/*.py /root/cam_*.sh 2>&1; echo ===; lsmod | grep -E "cam|sv"' 2>&1
