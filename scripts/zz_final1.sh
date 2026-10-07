#!/bin/sh
# Read the sensor's live geometry + CAMSV frame sequence, then capture a clean full frame.
I2C="i2ctransfer -f -y 10"
SEEK=4005

lsmod | grep -q cam_cap || insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0

echo "== sensor live registers =="
echo -n "  0x034C X_OUT : "; nice -n 19 $I2C w2@0x10 03 4c r2
echo -n "  0x034E Y_OUT : "; nice -n 19 $I2C w2@0x10 03 4e r2
echo -n "  0x0340 VMAX  : "; nice -n 19 $I2C w2@0x10 03 40 r2
echo -n "  0x0342 HMAX  : "; nice -n 19 $I2C w2@0x10 03 42 r2
echo -n "  0x0344 XSTA  : "; nice -n 19 $I2C w2@0x10 03 44 r2
echo -n "  0x0346 YSTA  : "; nice -n 19 $I2C w2@0x10 03 46 r2
echo -n "  0x0348 XEND  : "; nice -n 19 $I2C w2@0x10 03 48 r2
echo -n "  0x034A YEND  : "; nice -n 19 $I2C w2@0x10 03 4a r2
echo -n "  0x0900 BINH  : "; nice -n 19 $I2C w2@0x10 09 00 r1
echo -n "  0x0901 BINV  : "; nice -n 19 $I2C w2@0x10 09 01 r1
echo -n "  0x0902 BINT  : "; nice -n 19 $I2C w2@0x10 09 02 r1
echo -n "  0x0112 RAW   : "; nice -n 19 $I2C w2@0x10 01 12 r1
echo -n "  0x0114 LANE  : "; nice -n 19 $I2C w2@0x10 01 14 r1
echo -n "  0x0100 MODE  : "; nice -n 19 $I2C w2@0x10 01 00 r1

echo "== CAMSV FRAME_SEQ_NO (0x1a11075c) over 2 s =="
S1=$(busybox devmem 0x1a11075c 32)
sleep 2
S2=$(busybox devmem 0x1a11075c 32)
echo "  seq $S1 -> $S2"

echo "== clean full-frame capture: xsize=5000 stride=5000 ysize=1500 =="
nice -n 19 dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>/dev/null
echo cfg 1 0 4000 0 3000 5000 1500 5000 > /proc/camcap 2>/dev/null
echo arm > /proc/camcap 2>/dev/null
sleep 4
grep -E "int_status|frame_ready|last_seq|last_result" /proc/camcap_info
nice -n 19 dd if=/proc/camcap of=/root/fr.bin bs=1M count=16 2>/dev/null
md5sum /root/fr.bin
nice -n 19 python3 - <<'EOF'
d=open('/root/fr.bin','rb').read(16777216)
last=0
for i in range(0,len(d),4):
    if d[i:i+4]!=b'\0\0\0\0': last=i
print("  extent =", last+4)
print("  head:", " ".join(f"{b:02x}" for b in d[:24]))
EOF
echo DONE
