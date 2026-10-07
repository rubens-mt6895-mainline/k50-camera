#!/bin/bash
K=${WINHOME}/.ssh/${K50_KEY}
cp -f $K /tmp/${K50_KEY} && chmod 600 /tmp/${K50_KEY}
for f in f2_tpg f2_scene f2_bright; do
  scp -q -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      root@${K50_HOST}:/tmp/$f.bin ${K50_REPO}/frames/ && echo "got $f"
done
ls -l ${K50_REPO}/frames/f2_*.bin
