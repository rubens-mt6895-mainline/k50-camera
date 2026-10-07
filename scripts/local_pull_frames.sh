#!/bin/bash
# local_pull_frames.sh - PC/WSL side: pull captured frames off the phone.
set -u
cd ${K50_REPO}
K=/tmp/${K50_KEY}
cp -f ${WINHOME}/.ssh/${K50_KEY} "$K"
chmod 600 "$K"
SCP="scp -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

for f in ${FILES:-inl par par_auto}; do
	if timeout 180 $SCP "root@${K50_HOST}:/root/$f.yuyv" "frames/$f.yuyv"; then
		echo "pulled $f -> $(stat -c %s frames/$f.yuyv) bytes"
	else
		echo "FAILED $f"
	fi
done
ls -l frames/*.yuyv 2>/dev/null | tail -6
