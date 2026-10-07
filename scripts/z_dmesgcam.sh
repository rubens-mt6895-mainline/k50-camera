#!/bin/bash
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH 'dmesg | grep -iE "seninf|camsys|mtk-cam|imgsensor|imx582|mipi|camera|cci" | tail -30; echo "=== modules ==="; lsmod | grep -iE "cam|seninf|imgsensor|cci"; echo "=== streaming ctl ==="; echo skip' > ${K50_REPO}/out/dmesg_cam.log 2>/dev/null
echo DONE
