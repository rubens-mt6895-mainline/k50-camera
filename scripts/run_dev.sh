#!/bin/sh
# Push a device-side script to the phone and run it.
# usage: run_dev.sh <local-script> [args...]
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY" 2>/dev/null && chmod 600 "$KEY"
S="$1"; shift
B="$(basename "$S")"
/usr/bin/scp -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 \
  "$S" "root@${K50_HOST}:/root/$B" >/dev/null 2>&1 || { echo "scp failed ($B)"; exit 1; }
/usr/bin/ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 \
  "root@${K50_HOST}" "sh /root/$B $*"
