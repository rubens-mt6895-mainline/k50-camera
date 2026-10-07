#!/bin/bash
# zz_state.sh - read-only device state check (patterns chosen so they cannot
# match this command's own cmdline).
set -u
K=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$K"
chmod 600 "$K"
SSH="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

$SSH root@${K50_HOST} '
echo "=== stray readers ==="
pgrep -x grep; pgrep -x tail; pgrep -x v4l2-ctl
echo "=== camera procs ==="
ps -o pid,stat,wchan:22,etime,args -e | grep -E "v4l2-ctl|zz_|cheese" | grep -v grep
echo "=== cam_cap kthreads ==="
ps -eL -o pid,stat,wchan:22,comm | grep -i cam | head -14
echo "=== module ==="
grep -E "cam_cap" /proc/modules
echo "=== /proc/camcap_info (head 14) ==="
sed -n "1,14p" /proc/camcap_info 2>/dev/null
echo "=== loadavg ==="
cat /proc/loadavg
'
