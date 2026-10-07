#!/bin/bash
# local_pull_rb4.sh - pull the first frame of each forced-cast capture.
set -u
cd ${K50_REPO}
K=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$K"
chmod 600 "$K"
SSH="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

for f in ${FILES:-old_rb1_physR new_rb0_physR new_rb1_physB fixed_auto}; do
	if timeout 180 $SSH root@${K50_HOST} "head -c 6000000 /root/$f.yuyv" > "frames/$f.yuyv"; then
		echo "pulled $f -> $(stat -c %s "frames/$f.yuyv") bytes"
	else
		echo "FAILED $f"
	fi
done
