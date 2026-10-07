#!/bin/sh
# Determine whether the sensor sends 1500 or 3000 lines per frame.
# Read the CSI2 packet counter, then capture with GRAB_LIN set very high.
I2C="i2ctransfer -f -y 10"
SEEK=4005

grep -E "buffer_phys|buffer_dma" /proc/camcap_info
lsmod | grep -q cam_cap || insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0

echo "== sensor geometry =="
for r in "03 4e 0x034E Y_OUT" "03 4c 0x034C X_OUT" "03 40 0x0340 VMAX" "03 42 0x0342 HMAX" "09 00 0x0900 BINH" "09 01 0x0901 BINV"; do
  echo -n "  $r : "; nice -n 19 $I2C w2@0x10 $r r1
done

echo "== CSI2 packet counter (0x1a014adc) over 2 s =="
P1=$(busybox devmem 0x1a014adc 32); sleep 2; P2=$(busybox devmem 0x1a014adc 32)
echo "  p1=$P1 p2=$P2"

echo "== capture with GRAB_LIN=0xFFFF, ysize=3000, xsize=stride=5000 =="
nice -n 19 dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>&1 | tail -1
echo cfg 1 0 4000 0 65535 5000 3000 5000 > /proc/camcap
echo arm > /proc/camcap
sleep 4
nice -n 19 dd if=/proc/camcap of=/root/lin.bin bs=1M count=16 2>&1 | tail -1
nice -n 19 python3 - <<'EOF'
d=open('/root/lin.bin','rb').read(16777216)
last=0
for i in range(0,len(d),4):
    if d[i:i+4]!=b'\0\0\0\0': last=i
print("  extent(nonzero last byte+1) =", last+4)
nz=sum(1 for i in range(0,len(d),4) if d[i:i+4]!=b'\0\0\0\0')
print("  nonzero dwords =", nz)
print("  head:", " ".join(f"{b:02x}" for b in d[:32]))
EOF
grep -E "last_result|last_seq|int_status" /proc/camcap_info
echo DONE
