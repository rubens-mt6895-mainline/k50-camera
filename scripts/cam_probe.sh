#!/bin/bash
KEY=$HOME/.ssh/${K50_KEY}
OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes"
HOST=root@${K50_HOST}
ssh $OPTS $HOST 'printf "bootonce-bootloader\0\0" | dd of=/dev/sdc1 bs=512 count=1 conv=notrunc 2>/dev/null; dd if=/dev/sdc1 bs=512 count=1 2>/dev/null | head -c 20; echo; sync; reboot'
