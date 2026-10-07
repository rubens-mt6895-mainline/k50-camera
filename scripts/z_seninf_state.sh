#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'lsmod | grep -i -E "seninf|cam|imgsensor|cci"; echo "=== video devs ==="; ls /dev/video* 2>&1; echo "=== seninf dmesg ==="; dmesg | grep -i -E "seninf|imgsensor|mtk-cam|smi" | tail -20' > ${K50_REPO}/out/seninf_state.log 2>/dev/null
echo DONE
