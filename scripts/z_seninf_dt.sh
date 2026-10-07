#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'echo "=== seninf nodes ==="; ls /proc/device-tree/ | grep -i seninf; find /proc/device-tree -iname "*seninf*" 2>/dev/null | head; echo "=== regs ==="; for n in $(find /proc/device-tree -iname "*seninf*" -type d 2>/dev/null | head -3); do echo "-- $n"; cat $n/reg 2>/dev/null | xxd | head -3; cat $n/compatible 2>/dev/null | tr "\0" " "; echo; done' > ${K50_REPO}/out/seninf_dt.log 2>/dev/null
echo DONE
