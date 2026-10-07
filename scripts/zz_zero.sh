#!/bin/sh
# zz_zero.sh - work out where the IMGO DMA actually writes, by counting ZERO bytes
# after an explicit /dev/mem wipe of the CMA buffer.
nice -n 19 sh -c '
rmmod cam_cap 2>/dev/null; sleep 1
insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0 || exit 1
sleep 1
PHYS=$(grep -m1 "^buffer_phys" /proc/camcap_info | grep -o "0x[0-9a-fA-F]*" | tail -1)
[ -z "$PHYS" ] && PHYS=0xfa500000
SEEK=$((PHYS / 1048576))
echo "phys=$PHYS seek=$SEEK"
dmesg -C

run() {
	xs=$1; ys=$2; st=$3
	dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
	echo cfg 1 0 4000 0 $ys $xs $ys $st > /proc/camcap 2>/dev/null
	echo arm > /proc/camcap 2>/dev/null
	sleep 4
	python3 -c "
import sys
d=open(\"/proc/camcap\",\"rb\").read(16*1024*1024)
n=len(d.rstrip(b\"\x00\"))
z=d.count(0)
# zero runs
runs=[]; i=0; N=len(d)
while i<N:
    if d[i]==0:
        j=i
        while j<N and d[j]==0: j+=1
        runs.append((j-i,i)); i=j
    else: i+=1
runs.sort(reverse=True)
print(\"   xs=%-6s ys=%-5s st=%-6s extent=%-9d zeros=%-9d (%.1f%%) nzruns=%d top=\" % (\"$xs\",\"$ys\",\"$st\",n,z,100.0*z/N,len(runs)), runs[:4])
"
}
dmesg -C
run 2500 3000 2500
run 2500 3000 5000
run 5000 3000 5000
run 4000 3000 4000
dmesg | grep "cam_cap: arm" | tail -6
rmmod cam_cap 2>/dev/null
echo DONE
'
