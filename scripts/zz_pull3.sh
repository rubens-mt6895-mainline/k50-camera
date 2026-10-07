#!/bin/bash
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY}; chmod 600 /tmp/${K50_KEY}
O="-i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
for f in n_tpg n_scene n_bright; do
  timeout 240 scp $O root@${K50_HOST}:/tmp/$f.bin ${K50_REPO}/frames/$f.bin && ls -l ${K50_REPO}/frames/$f.bin
done
