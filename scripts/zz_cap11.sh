#!/bin/sh
# zz_cap11.sh - determine the true IMGO line length by varying xsize/stride.
rmmod cam_cap 2>/dev/null
sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0 2>/dev/null
echo "insmod rc=$?"
sleep 1

do_cfg() {
	echo "--- xsize=$1 stride=$2 ---"
	echo cfg 1 0 4000 0 3000 "$1" 3000 "$2" > /proc/camcap
	echo arm > /proc/camcap
	sleep 3
	python3 -c "
d=open('/proc/camcap','rb').read()
s=d.rstrip(b'\x00')
print('  size',len(d),'nonzero',len(d)-d.count(0),'last_nonzero',len(s)-1)
print('  head',d[:24].hex(' '))
"
}

do_cfg 5000 5000
do_cfg 4000 5000
do_cfg 8000 8000
do_cfg 2000 2500
do_cfg 10000 10000

echo "=== dmesg ==="
dmesg | grep -E "cam_cap: arm" | tail -8
rmmod cam_cap 2>/dev/null
echo "=== done ==="
