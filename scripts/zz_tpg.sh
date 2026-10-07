#!/bin/sh
# Enable the IMX582 test pattern (0x0601=2, 100% colour bar) and capture a frame,
# then capture one with the pattern off. Run on the device via zz_pushrun.sh.
I2C="i2ctransfer -f -y 10"
SEEK=4005
BUFPHYS=0xfa500000

echo "== module =="
lsmod | grep cam_cap || insmod /root/cam_cap.ko dbl_data_bus=1 pak_dbl=0
grep -E "buffer_phys|buffer_dma|iova" /proc/camcap_info

echo "== enable test pattern =="
nice -n 19 $I2C w3@0x10 0x06 0x01 0x02; echo "wr rc=$?"
echo -n "0x0601 = "; nice -n 19 $I2C w2@0x10 0x06 0x01 r1
echo -n "0x0100 = "; nice -n 19 $I2C w2@0x10 0x01 0x00 r1
echo -n "0x034C = "; nice -n 19 $I2C w2@0x10 0x03 0x4c r2

sleep 1
echo "== zero buffer =="
nice -n 19 dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>&1 | tail -1

echo "== cfg + arm (tpg ON) =="
echo cfg 1 0 4000 0 3000 2500 3000 2500 > /proc/camcap
echo arm > /proc/camcap
sleep 4
nice -n 19 dd if=/proc/camcap of=/root/tpg_on.bin bs=1M count=16 2>&1 | tail -1
md5sum /root/tpg_on.bin
grep -E "last_result|last_seq|int_status|last_int_st" /proc/camcap_info

echo "== disable test pattern =="
nice -n 19 $I2C w3@0x10 0x06 0x01 0x00; echo "wr rc=$?"
echo -n "0x0601 = "; nice -n 19 $I2C w2@0x10 0x06 0x01 r1
sleep 1

echo "== zero buffer again =="
nice -n 19 dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>&1 | tail -1
echo cfg 1 0 4000 0 3000 2500 3000 2500 > /proc/camcap
echo arm > /proc/camcap
sleep 4
nice -n 19 dd if=/proc/camcap of=/root/tpg_off.bin bs=1M count=16 2>&1 | tail -1
md5sum /root/tpg_off.bin
grep -E "last_result|last_seq|int_status" /proc/camcap_info
echo DONE
