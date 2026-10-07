#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i ~/.ssh/${K50_KEY} root@${K50_HOST} \
  'echo "=== lsmod cam/seninf ==="; lsmod | grep -iE "cam|seninf|mtk"; echo "=== dmesg seninf ==="; dmesg | grep -iE "seninf|mtk_cam" | tail -20; echo "=== /sys seninf ==="; ls /sys/bus/platform/drivers/ 2>/dev/null | grep -iE "seninf|cam"; ls /sys/class/video4linux/ 2>/dev/null'
echo DONE
