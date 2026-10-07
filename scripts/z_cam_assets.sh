#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'ls -la /root/*.py /root/cam_view 2>/dev/null; echo "=== sv/camsv ==="; ls /root/sv_* /root/camsv* /root/seninf* /root/frame* 2>/dev/null; echo "=== fb0 ==="; ls -la /dev/fb0 2>/dev/null; echo "=== xorg/kde ==="; echo "DISPLAY=$DISPLAY"; ls /tmp/.X11-unix/ 2>/dev/null; ps aux | grep -E "Xorg|kwin" | grep -v grep | head -3' > ${K50_REPO}/out/cam_assets.log 2>/dev/null
echo DONE
