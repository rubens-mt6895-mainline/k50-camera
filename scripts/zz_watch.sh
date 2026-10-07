#!/bin/bash
# Wait for the K50 to come back, then report status.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
SSH="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=6 -o BatchMode=yes root@${K50_HOST}"
for i in $(seq 1 20); do
  OUT=$(timeout 12 $SSH "date; uptime" 2>/dev/null)
  if echo "$OUT" | grep -q "up"; then
    echo "RECOVERED at attempt $i"
    echo "$OUT"
    exit 0
  fi
  echo "attempt $i: still down ($(date +%H:%M:%S))"
  sleep 20
done
echo "STILL_DOWN_after_20_attempts"
exit 2
