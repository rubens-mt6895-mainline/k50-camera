#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'echo "=== cam_cap modinfo ==="; modinfo /root/cam_cap.ko 2>/dev/null | grep -E "^description|^name|^vermagic"; echo "=== cam_probe_dbg ==="; modinfo /root/cam_probe_dbg.ko 2>/dev/null | grep -E "^description|^name|^vermagic"; echo "=== loaded? ==="; lsmod | grep -E "cam_cap|cam_probe"; echo "=== dmesg cam_cap/probe ==="; dmesg | grep -iE "cam_cap|cam_probe|camclk|cam_clk" | tail -25'
echo DONE
