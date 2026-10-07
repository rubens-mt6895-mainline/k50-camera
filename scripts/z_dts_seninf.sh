#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'ls /proc/device-tree/ 2>/dev/null | grep -iE "seninf|cam"; echo ===; find /proc/device-tree -maxdepth 2 -name "*seninf*" 2>/dev/null | head; echo ===; cat /proc/device-tree/mediatek/seninf*/compatible 2>/dev/null; echo; find /proc/device-tree -maxdepth 3 -type d -name "seninf*" 2>/dev/null'
echo DONE
