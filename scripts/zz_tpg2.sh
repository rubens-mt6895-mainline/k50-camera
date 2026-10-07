#!/bin/sh
# IMX582 test-pattern capture: 0x0601=0x02 (100% colour bar) ON, then OFF.
# The pattern is generated in the sensor, so it is immune to any light flicker.
I2C="i2ctransfer -f -y 10"
SEEK=4005          # 4005 MiB == 0xfa500000, the module's CMA buffer
CFG="cfg 1 0 4000 0 3000 4000 3000 5000"

show() { grep -E "vf_on|int_status|last_seq|last_result|frame_ready|arm_count" /proc/camcap_info; }

echo "== stop + baseline =="
echo stop > /proc/camcap 2>/dev/null
show
echo -n "0x0601 = "; nice -n 19 $I2C w2@0x10 0x06 0x01 r1

echo "== enable test pattern =="
nice -n 19 $I2C w3@0x10 0x06 0x01 0x02; echo "wr rc=$?"
sleep 1
echo -n "0x0601 = "; nice -n 19 $I2C w2@0x10 0x06 0x01 r1
echo -n "0x0100 = "; nice -n 19 $I2C w2@0x10 0x01 0x00 r1

echo "== zero buffer =="
nice -n 19 dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>&1 | tail -1

echo "== $CFG =="
echo "$CFG" > /proc/camcap
echo arm > /proc/camcap
sleep 6
show
nice -n 19 dd if=/proc/camcap of=/tmp/tpg_on.bin bs=1M count=16 2>&1 | tail -1
md5sum /tmp/tpg_on.bin

echo "== disable test pattern =="
nice -n 19 $I2C w3@0x10 0x06 0x01 0x00; echo "wr rc=$?"
sleep 1
echo -n "0x0601 = "; nice -n 19 $I2C w2@0x10 0x06 0x01 r1
echo "== zero buffer =="
nice -n 19 dd if=/dev/zero of=/dev/mem bs=1M count=16 seek=$SEEK conv=notrunc 2>&1 | tail -1
echo "== $CFG =="
echo "$CFG" > /proc/camcap
echo arm > /proc/camcap
sleep 6
show
nice -n 19 dd if=/proc/camcap of=/tmp/tpg_off.bin bs=1M count=16 2>&1 | tail -1
md5sum /tmp/tpg_off.bin
echo DONE
