#!/bin/bash
H="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
echo "=== cam_go.sh ==="
$H 'cat /root/cam_go.sh'
echo "=== i2cdetect ==="
$H 'for b in 8 10 11 12; do echo "-- i2c-$b --"; i2cdetect -y $b 2>/dev/null | grep -v "^  "; done'
echo DONE
