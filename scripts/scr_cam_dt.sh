#!/bin/bash
KEY=$HOME/.ssh/${K50_KEY}
OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=15"
ssh $OPTS root@${K50_HOST} '
echo "=== i2c buses / devices ==="
for i in /sys/bus/i2c/devices/*/name; do echo "$i: $(cat $i)"; done 2>/dev/null | head -30
echo
echo "=== DT camera / cci / cam nodes (from running dtb) ==="
ls /proc/device-tree/ 2>/dev/null
echo "--- look for cam/sensor/cci ---"
find /proc/device-tree -maxdepth 3 -iname "*cam*" -o -iname "*cci*" -o -iname "*sensor*" 2>/dev/null | head
echo
echo "=== any mtk camera driver in kernel modules ==="
find /lib/modules/$(uname -r) -iname "*cam*" -o -iname "*seninf*" -o -iname "*imgsys*" -o -iname "*ccic*" 2>/dev/null | head
echo
echo "=== uname ==="
uname -r
'
