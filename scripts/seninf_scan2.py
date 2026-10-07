#!/usr/bin/env python3
# seninf_scan2.py - correct port layout per SENINF_CONFIG.md:
#   SENINF port i: base = 0x1a010000 + 0x200 + i*0x2000
#   CSI2_EN = portbase+0x800, CSI2_IRQ = portbase+0x8C8, PKT_CNT = portbase+0x8D8
# Scan all 10 ports for incoming MIPI from streaming IMX582.
import mmap, os, struct, time, subprocess

IF_TOP = 0x1a010000
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_cache = {}
def _map(pg):
    if pg not in _cache:
        _cache[pg] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
    return _cache[pg]
def rd(addr):
    m = _map(addr & ~0xfff)
    return struct.unpack_from('<I', m, addr & 0xfff)[0]
def wr(addr, val):
    m = _map(addr & ~0xfff)
    struct.pack_into('<I', m, addr & 0xfff, val)

def i2c(*args):
    return subprocess.run(['i2ctransfer', '-f', '-y', *args], capture_output=True, text=True).stdout.strip()

# ensure streaming
print("ID16=%s ID17=%s" % (i2c('10','w2@0x10','0x00','0x16','r1'), i2c('10','w2@0x10','0x00','0x17','r1')), flush=True)
i2c('10','w3@0x10','0x01','0x00','0x01')
time.sleep(0.2)
fc1 = i2c('10','w2@0x10','0x00','0x05','r1')
time.sleep(0.4)
fc2 = i2c('10','w2@0x10','0x00','0x05','r1')
print("framecnt: %s -> %s (streaming=%s)" % (fc1, fc2, fc1 != fc2), flush=True)

print("--- scan 10 ports (stride 0x2000) ---", flush=True)
for i in range(10):
    pb = IF_TOP + 0x200 + i * 0x2000
    csi2_en = pb + 0x800
    # enable all 4 lanes
    wr(csi2_en, 0x0); time.sleep(0.002)
    wr(csi2_en, 0xF)
    time.sleep(0.5)
    en = rd(csi2_en)
    irq1 = rd(pb + 0x8C8)
    pkt1 = rd(pb + 0x8D8)   # PACKET_CNT per SENINF_CONFIG
    cnt1 = rd(pb + 0x8DC)
    time.sleep(0.5)
    irq2 = rd(pb + 0x8C8)
    pkt2 = rd(pb + 0x8D8)
    cnt2 = rd(pb + 0x8DC)
    act = '<<<DATA' if (pkt2 != pkt1 or cnt2 != cnt1 or irq2) else ''
    print("port%d(base=%08x): EN=%08x PKT=%08x->%08x CNT=%08x->%08x IRQ=%08x->%08x %s" %
          (i, pb, en, pkt1, pkt2, cnt1, cnt2, irq1, irq2, act), flush=True)
    wr(csi2_en, 0x0)
print("done", flush=True)
