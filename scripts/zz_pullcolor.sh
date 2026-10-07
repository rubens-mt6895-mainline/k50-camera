#!/bin/bash
K=${WINHOME}/.ssh/${K50_KEY}
cp -f $K /tmp/${K50_KEY} && chmod 600 /tmp/${K50_KEY}
scp -q -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    root@${K50_HOST}:/tmp/color_frame.bin ${K50_REPO}/frames/ && echo "got color_frame"
ls -l ${K50_REPO}/frames/color_frame.bin
