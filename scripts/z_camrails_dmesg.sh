#!/bin/bash
H="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$H 'dmesg | grep -iE "cam_rails|cam_genpd|cam_ovl|cam_clk|camclk" | tail -30'
echo DONE
