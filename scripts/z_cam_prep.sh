#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'echo "=== /root ko ==="; ls -la /root/*.ko 2>/dev/null; echo "=== /tmp ko ==="; ls -la /tmp/*.ko 2>/dev/null; echo "=== lsmod cam ==="; lsmod | grep -iE "cam|sv|seninf"; echo "=== push to /tmp ==="; cp /root/cam_*.ko /tmp/ 2>&1; ls -la /tmp/cam_*.ko' 2>&1
