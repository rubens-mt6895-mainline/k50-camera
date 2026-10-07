#!/bin/bash
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH '
echo "== dump 0x1A010300-0x1A010420 =="
for off in 300 310 320 330 340 350 360 370 380 390 3a0 3b0 3c0 3d0 3e0 3f0 400 410 420; do
  echo -n "1A01$off: "
  devmem 0x1A01$off
done
echo "== write test cammux ctrl0 =="
devmem 0x1A010400 32 0x00202000
devmem 0x1A010400
devmem 0x1A010410 32 0x0000000C
devmem 0x1A010410
' > ${K50_REPO}/out/cammux_probe.log 2>&1
echo DONE
