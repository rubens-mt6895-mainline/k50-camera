#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"
echo "=== device ==="
$H 'date; uptime; echo "--- lsmod ---"; lsmod'
echo "=== cron task (PC) ==="
grep -o '"id":"[^"]*"\|"title":"[^"]*"\|"schedule":"[^"]*"\|"enabled":[a-z]*\|"type":"[^"]*"' ${WINHOME}/.dsh/profiles/desktop/.dsh/data/cron/tasks.json 2>/dev/null | head -20
