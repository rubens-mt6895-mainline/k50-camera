#!/bin/sh
# zz_cap14.sh - sweep the SENINF pixel-mode / CAMSV double-bus settings and measure the
# total payload per frame.  7,500,000 B = half rate; 15,000,000 B = full rate.
test_combo() {
	px=$1; dbl=$2
	rmmod cam_cap 2>/dev/null
	sleep 1
	insmod /root/cam_cap.ko dbl_data_bus=$dbl pak_dbl=0 route_pix_mode=$px 2>/dev/null
	rc=$?
	echo "--- route_pix_mode=$px dbl_data_bus=$dbl (insmod rc=$rc) ---"
	sleep 1
	[ $rc -ne 0 ] && return
	PHYS=$(grep -m1 '^buffer_phys' /proc/camcap_info | grep -o '0x[0-9a-fA-F]*' | tail -1)
	[ -z "$PHYS" ] && PHYS=0xfa500000
	SEEK=$((PHYS / 1048576))
	dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
	echo cfg 1 0 4000 0 3000 5000 3000 5000 > /proc/camcap 2>/dev/null
	sleep 1
	echo arm > /proc/camcap 2>/dev/null
	sleep 4
	python3 -c "
d=open('/proc/camcap','rb').read()
s=d.rstrip(b'\x00')
print('   extent=%d nonzero=%d  -> bytes/line if 3000 lines = %.1f' % (len(s), len(d)-d.count(0), len(s)/3000.0))
"
}
test_combo 1 1
test_combo 2 1
test_combo 1 0
test_combo 2 0
test_combo 0 1
rmmod cam_cap 2>/dev/null
echo "=== done ==="
