#!/bin/sh
# cam_v6d.sh - post-LDO78 power change: RST + init + stream + FSM (2026-10-05)
LOG=/root/cam_v6d.log
: > $LOG
echo "=== cam_v6d $(date) ===" >> $LOG

# 1. RST pulse (GPIO155 low 100ms -> high)
busybox devmem 0x10005010 32 0x80020200   # clear bit27 (155 low), keep others
sleep 0.1
busybox devmem 0x10005010 32 0xC8020200   # 155 high
echo "rst pulsed" >> $LOG

# 2. init + stream
sh /root/cam_init.sh >> $LOG 2>&1
echo "--- key regs ---" >> $LOG
for pair in "0x01 0x00:0x0100" "0x01 0x14:0x0114" "0x01 0x15:0x0115" "0x03 0x07:0x0307"; do
  addr="${pair%%:*}"; reg="${pair##*:}"
  echo "reg $reg = $(i2ctransfer -f -y 10 w2@0x10 $addr r1 2>&1)" >> $LOG
done

# 3. framecnt + FSM
echo "--- framecnt ---" >> $LOG
echo "framecnt = $(i2ctransfer -f -y 10 w2@0x10 0x00 0x05 r1 2>&1)" >> $LOG
echo "--- FSM x3 ---" >> $LOG
python3 -c "
import mmap, os, struct, time
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_cache = {}
def rd(addr):
    pg = addr & ~0xfff
    if pg not in _cache: _cache[pg] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
    return struct.unpack_from('<I', _cache[pg], addr & 0xfff)[0]
ANA = 0x11C80000
DPHYS = {0: ANA+0x2000, 1: ANA+0x12000, 2: ANA+0x6000, 3: ANA+0x16000, 4: ANA+0xa000, 5: ANA+0xe000}
for k in range(3):
    line = []
    for n, base in DPHYS.items():
        line.append('D%d:%08x/%08x' % (n, rd(base+0x30), rd(base+0x34)))
    print('t%d %s' % (k, ' '.join(line)))
    time.sleep(0.3)
" >> $LOG 2>&1

echo "=== done ===" >> $LOG
