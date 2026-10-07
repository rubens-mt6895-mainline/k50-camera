#!/bin/sh
# cam_v6_run.sh - IMX582 init + stream + SENINF FSM dump (2026-10-05)
LOG=/root/cam_v6.log
: > $LOG
echo "=== cam_v6_run start $(date) ===" >> $LOG

# 1. IMX582 ID
ID16=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1)
ID17=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>&1)
echo "ID16=$ID16 ID17=$ID17" >> $LOG

# 2. cam_init（236 寄存器）
echo "--- cam_init ---" >> $LOG
sh /root/cam_init.sh >> $LOG 2>&1

# 3. 回读关键寄存器
echo "--- key regs ---" >> $LOG
for pair in "0x01 0x00:0x0100" "0x01 0x14:0x0114" "0x01 0x15:0x0115" "0x03 0x07:0x0307"; do
  addr="${pair%%:*}"; reg="${pair##*:}"
  v=$(i2ctransfer -f -y 10 w2@0x10 $addr r1 2>&1)
  echo "reg $reg = $v" >> $LOG
done

# 4. streaming on
i2ctransfer -f -y 10 w2@0x10 0x01 0x00 0x01 >> $LOG 2>&1
sleep 0.5
S=$(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1)
echo "0x0100 after stream-on = $S" >> $LOG

# 5. SENINF RX 配置（口1 ANA1B + DPHY_TOP_1）： 依 memory §9.4e
echo "--- SENINF RX cfg ---" >> $LOG
python3 -c "
import mmap, os, struct
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
def mm(base, size=0x1000):
    return mmap.mmap(f, size, mmap.MAP_SHARED, base)
def rd(m, off):
    return struct.unpack_from('<I', m, off)[0]
def wr(m, off, val):
    struct.pack_into('<I', m, off, val)
try:
    # DPHY_TOP_1 = 0x11C86000; ANA1B = 0x11C85000 (per memory 9.4d)
    dphy = mm(0x11C86000, 0x2000)
    ana  = mm(0x11C85000, 0x2000)
    # RX lane enable: DPHY_RX_LANE_EN etc per full_dphy.py findings
    for off, val in [(0x00, 0xF01), (0x08, 0xF01)]:
        wr(dphy, off, val)
    for off in (0x00, 0x04, 0x08, 0x10, 0x180):
        print('DPHY_TOP_1+0x%03x = 0x%08x' % (off, rd(dphy, off)), file=open('$LOG','a'))
    # ANA RX enable
    wr(ana, 0x00, 0x1)
    for off in (0x00, 0x04):
        print('ANA1B+0x%03x = 0x%08x' % (off, rd(ana, off)), file=open('$LOG','a'))
    m.close()
except Exception as e:
    print('RX cfg err:', e, file=open('$LOG','a'))
" 2>&1 >> $LOG

# 6. FSM dump（口1 CL0/DL0-3）
echo "--- FSM after stream ---" >> $LOG
python3 -c "
import mmap, os, struct, time
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(f, 0x2000, mmap.MAP_SHARED, 0x11C86000)
def rd(off):
    return struct.unpack_from('<I', m, off)[0]
# DPHY FSM offsets (per all_ports_full.py / sweep_b findings)
# CL0 at +0x40?, DL at +0x44..  -- 探测常见 FSM 区
for base in (0x0, 0x40, 0x80, 0x100):
    print('DPHY+0x%03x: ' % base, ' '.join('0x%08x' % rd(base+o*4) for o in range(4)), file=open('$LOG','a'))
m.close()
" 2>&1 >> $LOG

# 7. SENINF 口1 帧计数（CSI2 PACKET_CNT）
echo "--- CSI2 PKT (seninf port1) ---" >> $LOG
python3 -c "
import mmap, os, struct, time
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(f, 0x2000, mmap.MAP_SHARED, 0x1a010000)
def rd(off):
    return struct.unpack_from('<I', m, off)[0]
for off in (0x0, 0x4, 0x8, 0xC, 0x40, 0x100, 0x104):
    print('SENINF+0x%03x = 0x%08x' % (off, rd(off)), file=open('$LOG','a'))
m.close()
" 2>&1 >> $LOG

echo "=== cam_v6_run done ===" >> $LOG
