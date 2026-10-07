#!/bin/sh
# Test pattern ON, but now with xsize=5000 (bytes) so a full 4000-px RAW10 line is written.
I2C="i2ctransfer -f -y 10"
SEEK=4005
CFG="cfg 1 0 4000 0 3000 5000 3000 5000"

echo "== TPG on =="
nice -n 19 $I2C w3@0x10 0x06 0x01 0x02; echo "rc=$?"
sleep 1
echo -n "0x0601 = "; nice -n 19 $I2C w2@0x10 0x06 0x01 r1

echo "== zero =="
nice -n 19 dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>&1 | tail -1

echo "== $CFG =="
echo "$CFG" > /proc/camcap
echo arm > /proc/camcap
sleep 8
grep -E "vf_on|int_status|last_seq|last_result|frame_ready" /proc/camcap_info
nice -n 19 dd if=/proc/camcap of=/tmp/tpg5.bin bs=1M count=16 2>&1 | tail -1
md5sum /tmp/tpg5.bin
echo "== TPG off =="
nice -n 19 $I2C w3@0x10 0x06 0x01 0x00; echo "rc=$?"
sleep 1
echo -n "0x0601 = "; nice -n 19 $I2C w2@0x10 0x06 0x01 r1
echo DONE
