#!/bin/sh
# zz_cap15.sh - sweep TG_SEN_GRAB_LIN / ysize to see whether the 7,500,000 B payload is
# limited by the sensor (fixed) or by the TG line count (scales).
AN=/root/an15.py
cat > $AN <<'EOF'
import sys
stride=int(sys.argv[1])
d=open('/proc/camcap','rb').read()
s=d.rstrip(b'\x00'); ext=len(s)
print('   extent=%d nonzero=%d rows@%d=%d' % (ext, len(d)-d.count(0), stride, ext//stride))
EOF

rmmod cam_cap 2>/dev/null
sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0 2>/dev/null
echo "insmod rc=$?"
sleep 1
PHYS=$(grep -m1 '^buffer_phys' /proc/camcap_info | grep -o '0x[0-9a-fA-F]*' | tail -1)
[ -z "$PHYS" ] && PHYS=0xfa500000
SEEK=$((PHYS / 1048576))
echo "phys=$PHYS"

run() {	# pxl_end lin_end xsize ysize stride
	dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
	echo "--- pxl 0..$1  lin 0..$2  xsize=$3 ysize=$4 stride=$5 ---"
	echo cfg 1 0 $1 0 $2 $3 $4 $5 > /proc/camcap 2>/dev/null
	sleep 1
	echo arm > /proc/camcap 2>/dev/null
	sleep 4
	python3 $AN $5
}

run 4000 3000 2500 3000 2500
run 4000 6000 2500 6000 2500
run 4000 1500 2500 1500 2500
run 4000 3000 2500 1500 2500
run 8000 3000 5000 3000 5000

dmesg | grep -E "cam_cap: arm" | tail -5
rmmod cam_cap 2>/dev/null
echo "=== done ==="
