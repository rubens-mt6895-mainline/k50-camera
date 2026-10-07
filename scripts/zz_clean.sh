#!/bin/bash
# zz_clean.sh - clean up a zz_rate.sh run that hung on `grep ... /dev/kmsg`
# (/dev/kmsg never reaches EOF, so grep|tail blocks forever).
set -u
K=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$K"
chmod 600 "$K"
SSH="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

$SSH root@${K50_HOST} '
for p in $(pgrep -f zz_rate.sh); do echo "kill zz_rate.sh pid $p"; kill -9 "$p"; done
for p in $(pgrep -f "kmsg"); do echo "kill kmsg reader pid $p"; kill -9 "$p"; done
for p in $(pgrep -x grep); do echo "kill grep pid $p"; kill -9 "$p"; done
echo "=== remaining camera procs ==="
ps -o pid,stat,wchan:22,etime,args -e | grep -E "v4l2-ctl|zz_rate|cheese" | grep -v grep
echo "=== cam_cap threads ==="
ps -eLf 2>/dev/null | grep -E "cam_cap" | grep -v grep | head -12
echo "=== /proc/camcap_info (head) ==="
sed -n "1,14p" /proc/camcap_info 2>/dev/null
echo "=== loadavg ==="
cat /proc/loadavg
'
