#!/bin/sh
# zz_linlen.sh - measure the real byte length of one sensor line, by grabbing
# a tiny number of lines with a huge XSIZE/STRIDE so nothing is cut off.
nice -n 19 sh -c '
rmmod cam_cap 2>/dev/null; sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0 || exit 1
sleep 1
PHYS=$(grep -m1 "^buffer_phys" /proc/camcap_info | grep -o "0x[0-9a-fA-F]*" | tail -1)
[ -z "$PHYS" ] && PHYS=0xfa500000
SEEK=$((PHYS / 1048576))
echo "buffer phys=$PHYS seek=$SEEK"
dmesg -C

measure() {
	lin=$1; ysize=$2
	dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
	echo cfg 1 0 4000 0 $lin 8192 $ysize 8192 > /proc/camcap
	echo arm > /proc/camcap
	sleep 3
	python3 -c "
import sys
d=open(\"/proc/camcap\",\"rb\").read(2*1024*1024)
n=len(d.rstrip(b\"\x00\"))
print(\"   lines=%-5s ysize=%-5s -> extent=%d  bytes/line=%s\" % (\"$lin\",\"$ysize\",n, (\"%.1f\"%(n/$ysize)) if $ysize else \"-\"))
"
}
for L in 1 2 4 16 64; do measure $L $L; done
echo "--- arm results ---"
dmesg | grep -E "cam_cap: arm" | tail -8
echo "--- xsize experiment: does XSIZE cut the line? ---"
dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
echo cfg 1 0 4000 0 16 2500 16 2500 > /proc/camcap
echo arm > /proc/camcap
sleep 3
python3 -c "
d=open(\"/proc/camcap\",\"rb\").read(1024*1024)
n=len(d.rstrip(b\"\x00\"))
print(\"   xsize=2500 stride=2500 ysize=16 -> extent=%d (16*2500=%d)\" % (n, 16*2500))
"
rmmod cam_cap 2>/dev/null
echo DONE
'
