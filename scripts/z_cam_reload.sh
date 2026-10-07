#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'for m in cam_clk3 cam_clk cam_clk2 cam_rails cam_genpd cam_ovl; do rmmod $m 2>&1 | tail -1; done; sleep 1; for m in cam_ovl cam_genpd cam_rails cam_clk2 cam_clk cam_clk3; do insmod /root/$m.ko 2>&1 | tail -1; sleep 0.5; done; lsmod | grep cam_'
echo "=== after reload ==="
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'i2cdetect -y 10 2>/dev/null | grep "10:"'
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'grep -c "camtg3_ck" /sys/kernel/debug/clk/camtg3_ck/clk_rate 2>/dev/null; cat /sys/kernel/debug/clk/camtg3_ck/clk_rate 2>/dev/null'
echo DONE
