#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'sh /root/cam_load.sh 2>&1; echo "=== lsmod ==="; lsmod | grep -iE "cam|sv"; echo "=== dmesg tail ==="; dmesg | tail -30' 2>&1
