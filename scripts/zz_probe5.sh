#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} '
echo "== cmdline =="; cat /proc/cmdline
echo "== mounts =="; cat /proc/mounts | head -12
echo "== /boot =="; ls -l /boot 2>/dev/null | head -30
echo "== find dtb on disk =="; ls -l /*.dtb /boot/*.dtb /boot/dtb* 2>/dev/null | head -20
echo "== what is / attached to =="; lsblk 2>/dev/null || cat /proc/partitions
echo "== debugfs top =="; ls /sys/kernel/debug/ | head -40
echo "== dev spmi =="; ls -l /dev | grep -iE "spmi|mem|i2c" | head -20
echo "== spmi devices detail =="; for d in /sys/bus/spmi/devices/*; do echo -n "$d: "; tr -d "\0" < $d/modalias 2>/dev/null; echo; done
echo "== spmi controllers =="; ls /sys/class/spmi_host /sys/class/spmi_master 2>/dev/null
echo "== regulator class count =="; ls /sys/class/regulator | wc -l
'
