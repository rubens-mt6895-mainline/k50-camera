#!/bin/bash
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH 'cat /root/cam_go.sh; echo =====; cat /root/cam_init.sh | head -5; echo =====; ls /sys/class/gpio/ 2>/dev/null | head; echo =====; grep -i "iovdd\|vddio\|vdd_en\|pdn\|rst\|mclk" /sys/kernel/debug/gpio 2>/dev/null | head -30'
