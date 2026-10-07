#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=6 -o BatchMode=yes root@${K50_HOST} 'date; uptime' 2>&1 || echo "DEVICE_OFFLINE"
