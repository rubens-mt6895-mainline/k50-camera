#!/bin/bash
H="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
echo "=== cam_load.sh content ==="
$H 'cat /root/cam_load.sh'
echo "=== insmod one by one ==="
$H 'for m in cam_ovl cam_genpd cam_rails cam_clk2 cam_clk cam_clk3; do insmod /root/$m.ko 2>&1 | tail -1; done; lsmod | grep cam_'
echo DONE
