#!/bin/bash
echo "=== pull cam_ovl.ko ==="
scp -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i ~/.ssh/${K50_KEY} \
  root@${K50_HOST}:/root/cam_ovl.ko ${K50_REPO}/out/cam_ovl.ko
echo "=== cam_ovl sections ==="
aarch64-linux-gnu-readelf -S ${K50_REPO}/out/cam_ovl.ko 2>&1 | grep -E "plt|modinfo|text|data" | head -12
echo "=== cam_ovl symbols relocations ==="
aarch64-linux-gnu-readelf -r ${K50_REPO}/out/cam_ovl.ko 2>&1 | grep -E "of_overlay|printk|R_AARCH64" | head -8
echo "=== cam_ovl modinfo ==="
modinfo ${K50_REPO}/out/cam_ovl.ko 2>&1 | head -8
