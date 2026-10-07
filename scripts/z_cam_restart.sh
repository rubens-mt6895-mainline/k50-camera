#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'echo "=== lsmod ==="; lsmod | grep -E "cam_|ccci" ; echo "=== load if missing ==="; ls /root/cam_load.sh >/dev/null 2>&1 && (lsmod | grep -q cam_ovl || sh /root/cam_load.sh); sleep 1; echo "=== cam_go ==="; sh /root/cam_go.sh; echo "=== retry ID ==="; i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1; i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1; echo "=== framecnt x2 ==="; i2ctransfer -f -y 10 w2@0x10 0x00 0x05 r1; sleep 0.5; i2ctransfer -f -y 10 w2@0x10 0x00 0x05 r1'
echo DONE
