#!/bin/bash
KEY=$HOME/.ssh/${K50_KEY}
OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o BatchMode=yes"
HOST=root@${K50_HOST}
ssh $OPTS $HOST 'cat /sys/block/sdc/sdc43/size; dd if=/dev/sdc43 of=/root/boot_cam.img bs=4M count=24 2>&1 | tail -1; ls -la /root/boot_cam.img; md5sum /root/boot_cam.img'
scp $OPTS $HOST:/root/boot_cam.img ${K50_REPO}/out/boot_cam.img >/dev/null 2>&1
ls -la ${K50_REPO}/out/boot_cam.img
