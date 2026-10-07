#!/bin/sh
# zz_exp.sh - is the CAMSV payload real image data?  Change the IMX582 shutter time
# and watch the payload statistics.  0x0202/0x0203 = SHR (exposure).
wr() {
	hi=$(echo $1 | cut -c1-2); lo=$(echo $1 | cut -c3-4)
	dh=$(echo $2 | cut -c1-2); dl=$(echo $2 | cut -c3-4)
	i2ctransfer -f -y 10 w4@0x10 0x$hi 0x$lo 0x$dh 0x$dl >/dev/null 2>&1
}
rd16() {
	hi=$(echo $1 | cut -c1-2); lo=$(echo $1 | cut -c3-4)
	i2ctransfer -f -y 10 w2@0x10 0x$hi 0x$lo r2 2>/dev/null
}

rmmod cam_cap 2>/dev/null
sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0 2>/dev/null
sleep 1
PHYS=$(grep -m1 '^buffer_phys' /proc/camcap_info | grep -o '0x[0-9a-fA-F]*' | tail -1)
[ -z "$PHYS" ] && PHYS=0xfa500000
SEEK=$((PHYS / 1048576))
echo cfg 1 0 4000 0 3000 2500 3000 2500 > /proc/camcap
echo "buffer phys=$PHYS"

capture() {
	out=$1
	dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
	echo arm > /proc/camcap
	sleep 4
	dd if=/proc/camcap of=$out bs=1M count=16 2>/dev/null
	python3 -c "
import sys
d=open('$out','rb').read()
s=d.rstrip(b'\x00')
print('   $out extent=%d mean_byte=%.2f max=%d' % (len(s), sum(d[:len(s)])/max(1,len(s)), max(d[:len(s)]) if len(s) else 0))
"
}

echo "--- shutter 0x0004 (very short) ---"
wr 0202 0004
sleep 2
echo "   readback 0x0202/03 = $(rd16 0202)"
capture /root/f14_short.bin

echo "--- shutter 0x0800 (long) ---"
wr 0202 0800
sleep 2
echo "   readback 0x0202/03 = $(rd16 0202)"
capture /root/f14_long.bin

echo "--- shutter 0x0004 again (back to dark) ---"
wr 0202 0004
sleep 2
capture /root/f14_dark2.bin

md5sum /root/f14_short.bin /root/f14_long.bin /root/f14_dark2.bin
rmmod cam_cap 2>/dev/null
echo "=== done ==="
