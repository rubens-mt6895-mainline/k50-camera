#!/bin/sh
# zz_cap9.sh - sweep the TG/PAK data-bus parameters and compare the captured bytes.
run_combo() {
	label="$1"; shift
	rmmod cam_cap 2>/dev/null
	sleep 1
	insmod /root/cam_cap.ko "$@" 2>/dev/null
	if [ $? -ne 0 ]; then
		echo "$label: insmod FAILED"
		return
	fi
	echo cfg 1 0 4000 0 3000 4000 3000 5000 > /proc/camcap
	echo arm > /proc/camcap
	sleep 1
	dd if=/proc/camcap of=/tmp/c.bin bs=1024 count=100 2>/dev/null
	nz=$(od -An -tx4 -v /tmp/c.bin | tr -s ' ' '\n' | grep -v '^$' | grep -vc '^00000000$')
	md=$(md5sum /tmp/c.bin | cut -d' ' -f1)
	hx=$(od -An -tx4 -N32 /tmp/c.bin | tr -s ' ')
	echo "$label: nz(100K dwords)=$nz md5=$md head=$hx"
	rmmod cam_cap 2>/dev/null
}

echo "=== baseline (dbl=1 as before) ==="
run_combo "dbl=1" dbl_data_bus=1
echo "=== sweep DBL_DATA_BUS ==="
run_combo "dbl=0" dbl_data_bus=0
run_combo "dbl=2" dbl_data_bus=2
run_combo "dbl=3" dbl_data_bus=3
echo "=== PAK_DBL_MODE sweep ==="
run_combo "dbl=1 pakdbl=0" dbl_data_bus=1 pak_dbl=0
run_combo "dbl=1 pakdbl=1" dbl_data_bus=1 pak_dbl=1
run_combo "dbl=1 pakdbl=2" dbl_data_bus=1 pak_dbl=2
echo "=== independent: dbl=0 pakdbl=0 ==="
run_combo "dbl=0 pakdbl=0" dbl_data_bus=0 pak_dbl=0
echo "=== route_pix_mode sweep ==="
run_combo "dbl=1 pxmode=0" dbl_data_bus=1 route_pix_mode=0
run_combo "dbl=1 pxmode=2" dbl_data_bus=1 route_pix_mode=2
echo "=== done ==="
