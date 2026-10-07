#!/bin/bash
# WSL-side: quick liveness / state probe of the K50.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}; chmod 600 /tmp/${K50_KEY}
H=root@${K50_HOST}
O="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
timeout 40 ssh $O $H '
uptime
echo "---lsmod---"; lsmod
echo "---proc---"; ls -l /proc/camcap /proc/camcap_info 2>&1
echo "---info---"; head -45 /proc/camcap_info 2>&1
echo "---i2c---"
echo -n "0x0100="; i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1
echo -n "0x0601="; i2ctransfer -f -y 10 w2@0x10 0x06 0x01 r1 2>&1
echo -n "0x034C="; i2ctransfer -f -y 10 w2@0x10 0x03 0x4c r2 2>&1
echo "---bins---"; ls -l /root/*.bin /tmp/*.bin 2>&1 | head
' 2>&1
