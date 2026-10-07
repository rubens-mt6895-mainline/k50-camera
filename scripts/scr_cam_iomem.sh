#!/bin/bash
KEY=$HOME/.ssh/${K50_KEY}
OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=15"
ssh $OPTS root@${K50_HOST} '
echo "=== block partitions ==="
ls -l /dev/disk/by-partlabel/ 2>/dev/null
echo
echo "=== /proc/iomem: camera/cci/cam/seninf/imgsys ranges ==="
grep -iE "cam|cci|seninf|imgsys|csi|0x150|0x151|0x152|0x153" /proc/iomem 2>/dev/null | head -40
echo
echo "=== mclk / cam clock in DT? ==="
ls /proc/device-tree/ 2>/dev/null | grep -iE "clk|cam"
echo
echo "=== available free/unclaimed high MMIO around camera base ==="
cat /proc/iomem 2>/dev/null | head -60
'
