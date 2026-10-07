#!/bin/bash
# zz_pull_cheese.sh - pull the frames decoded from cheese's webm recording.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
for f in cf_055 cf_056 cf_057; do
	timeout 120 scp $OPTS "root@${K50_HOST}:/tmp/$f.png" "${K50_REPO}/frames/cheese_$f.png" >/dev/null 2>&1
	echo "$f rc=$?"
done
ls -l ${K50_REPO}/frames/cheese_*.png
