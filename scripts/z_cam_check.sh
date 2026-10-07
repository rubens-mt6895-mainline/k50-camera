#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'lsmod | grep cam_; echo ---; ls /root/*.ko 2>/dev/null | head; echo ---; i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1; echo ---; ls /root/cam_load.sh /root/cam_go.sh 2>&1'
echo DONE
