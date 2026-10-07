#!/bin/bash
K=${WINHOME}/.ssh/${K50_KEY}
cp -f $K /tmp/${K50_KEY} && chmod 600 /tmp/${K50_KEY}
for f in pos2_0400 pos2_0800 pos2_1000; do
  scp -q -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      root@${K50_HOST}:/tmp/$f.bin ${K50_REPO}/frames/ && echo "got $f"
done
ls -l ${K50_REPO}/frames/pos2_*.bin
