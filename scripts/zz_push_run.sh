#!/bin/sh
# WSL-side driver: push the current build + a device script and run it.
# usage: zz_push_run.sh <device-script-name>
set -e
S="$1"
KEY=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$KEY"
chmod 600 "$KEY"
H=root@${K50_HOST}
O="-i $KEY -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10"
/usr/bin/scp $O ${K50_REPO}/out/camcap_0b8dd2e/cam_cap.ko "$H:/root/cam_cap.ko.new" >/dev/null
/usr/bin/scp $O "${K50_REPO}/out/re/$S" "$H:/root/$S" >/dev/null
/usr/bin/ssh $O "$H" "sh /root/$S"
