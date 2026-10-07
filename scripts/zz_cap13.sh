#!/bin/sh
# zz_cap13.sh - clean capture at xsize=stride=2500 (the geometry that yields 3000 full rows)
rmmod cam_cap 2>/dev/null
sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0 2>/dev/null
sleep 1
PHYS=$(grep -m1 '^buffer_phys' /proc/camcap_info | grep -o '0x[0-9a-fA-F]*' | tail -1)
SEEK=$((PHYS / 1048576))
dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>&1 | tail -1
echo cfg 1 0 4000 0 3000 2500 3000 2500 > /proc/camcap
echo arm > /proc/camcap
sleep 3
dd if=/proc/camcap of=/root/frame13.bin bs=1M count=16 2>&1 | tail -1
md5sum /root/frame13.bin
python3 -c "
d=open('/root/frame13.bin','rb').read()
s=d.rstrip(b'\x00')
print('extent',len(s),'nonzero',len(d)-d.count(0))
"
dmesg | grep -E "cam_cap: arm" | tail -3
rmmod cam_cap 2>/dev/null
echo done
