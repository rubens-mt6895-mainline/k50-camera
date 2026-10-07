#!/bin/bash
# zz_pull_webm_head.sh - pull the head frames decoded from cheese's recordings.
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}
chmod 600 /tmp/${K50_KEY}
OPTS="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
for f in hd_2026-10-06-201246_000 hd_2026-10-06-201246_001 hd_2026-10-06-201246_002 hd_2026-10-06-201246_003 \
	hd_2026-10-06-201401_000 hd_2026-10-06-201401_001 hd_2026-10-06-201401_002 hd_2026-10-06-201401_003; do
	timeout 120 scp $OPTS "root@${K50_HOST}:/tmp/$f.png" "${K50_REPO}/frames/$f.png" >/dev/null 2>&1
	echo "$f rc=$?"
done
ls -l ${K50_REPO}/frames/hd_*.png
