#!/bin/bash
echo "=== lsmod cam ==="
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'lsmod | grep cam_'
echo "=== /root ko files ==="
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'ls /root/*.ko 2>&1 | head -20'
echo "=== scripts ==="
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'ls -la /root/cam_load.sh /root/cam_go.sh 2>&1'
echo "=== i2c bus ==="
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'ls /dev/i2c-* 2>&1'
echo DONE
