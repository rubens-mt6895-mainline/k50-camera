#!/bin/sh
# zz_cap12.sh - zero the CMA buffer via /dev/mem, then measure the real DMA extent per cfg.
AN=/root/an12.py
cat > $AN <<'EOF'
import sys
stride=int(sys.argv[1])
d=open('/proc/camcap','rb').read()
nz=len(d)-d.count(0)
s=d.rstrip(b'\x00'); ext=len(s)
print('   extent=%d nonzero=%d rows@%d=%d' % (ext,nz,stride,ext//stride))
for r in range(3):
    seg=d[r*stride:(r+1)*stride]
    t=len(seg.rstrip(b'\x00'))
    print('   row%d nonzero=%d last_nonzero_in_row=%d' % (r,len(seg)-seg.count(0),t-1))
print('   head',d[:20].hex(' '))
EOF

rmmod cam_cap 2>/dev/null
sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0 2>/dev/null
echo "insmod rc=$?"
sleep 1
echo "--- info ---"
cat /proc/camcap_info

PHYS=$(grep -m1 '^buffer_phys' /proc/camcap_info | grep -o '0x[0-9a-fA-F]*' | tail -1)
[ -z "$PHYS" ] && PHYS=0xfa500000
SEEK=$((PHYS / 1048576))
echo "phys=$PHYS seek=$SEEK"

zero_buf() {
	dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>&1 | tail -1
}

run_cfg() {
	xs=$1; st=$2
	zero_buf
	echo "--- xsize=$xs stride=$st (after zeroing) ---"
	echo cfg 1 0 4000 0 3000 $xs 3000 $st > /proc/camcap
	sleep 1
	echo arm > /proc/camcap
	sleep 3
	python3 $AN $st
}

run_cfg 5000 5000
run_cfg 2500 2500
run_cfg 2000 2500
run_cfg 4000 5000

echo "=== dmesg ==="
dmesg | grep -E "cam_cap: arm" | tail -6
rmmod cam_cap 2>/dev/null
echo "=== done ==="
