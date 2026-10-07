#!/bin/bash
H="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$H 'lsmod | grep cam_'
echo "=== dmesg cam clk tail ==="
$H 'dmesg | grep -iE "camclk|cam_clk|cammux|mclk" | tail -12'
echo DONE
