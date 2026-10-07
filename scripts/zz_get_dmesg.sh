#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST} '
uptime
echo "--- lsmod m6315 ---"
lsmod | grep m6315
echo "--- dmesg m6315 lines ---"
dmesg | grep -E "m6315:|Internal error|pc :" | tail -45
'
