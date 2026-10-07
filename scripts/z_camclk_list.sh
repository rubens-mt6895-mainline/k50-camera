#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'dmesg | grep -i "camclk" | tail -80'
echo DONE
