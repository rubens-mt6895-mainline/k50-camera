#!/usr/bin/env python3
# seninf_scan.py - full CSI2 init (analog+digital) then scan all 5 seninf
# ports for incoming MIPI data from streaming IMX582.
import mmap, os, struct, time, subprocess

IF_BASE = 0x1a010000
ANA_BASE = 0x11c80000
SETTLE_DT = 0x10
HS_TRAIL = 0x34

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
def rmw(addr, mask, val):
    wr(addr, (rd(addr) & ~mask) | (val & mask))
def bits(addr, shift, mw, val):
    rmw(addr, ((1 << mw) - 1) << shift, val << shift)

def lane_param():
    return (2 << 0) | (HS_TRAIL << 8) | (SETTLE_DT << 16) | (1 << 28) | (1 << 29)

def setup_port(sidx, rx_off, dphy_off):
    rx = ANA_BASE + rx_off
    dphy = ANA_BASE + dphy_off
    ctrl = IF_BASE + 0x200 + 0x1000 * (sidx - 1)
    csi2 = IF_BASE + 0xA00 + 0x1000 * (sidx - 1)
    rmw(rx + 0x20, 0x3f << 16, 0)
    rmw(rx + 0x0, 0x2, 0)
    rmw(rx + 0x0, 0x1, 0)
    time.sleep(0.0002)
    rmw(rx + 0x0, 0x1, 0x1)
    time.sleep(0.00003)
    rmw(rx + 0x0, 0x2, 0x2)
    rmw(rx + 0x20, 0x3f << 16, 0x3f << 16)
    time.sleep(0.000001)
    bits(rx + 0x04, 0, 3, 0x4)
    bits(rx + 0x04, 4, 3, 0x4)
    bits(rx + 0x08, 28, 3, 0x4)
    bits(rx + 0x08, 24, 3, 0x4)
    bits(rx + 0x04, 8, 4, 0x8)
    bits(rx + 0x04, 16, 3, 0x2)
    bits(rx + 0x14, 0, 2, 0x3)
    bits(rx + 0x14, 2, 2, 0x1)
    bits(rx + 0x14, 6, 1, 0x1)
    bits(rx + 0x14, 4, 1, 0x1)
    bits(rx + 0x14, 5, 1, 0x1)
    bits(rx + 0x14, 8, 4, 0x0)
    bits(rx + 0x14, 12, 4, 0x0)
    rmw(rx + 0x24, 0xffff << 16, 0x3003 << 16)
    rmw(rx + 0xf0, 0x3 << 16, 0x2 << 16)
    bits(rx + 0x08, 0, 5, 0x10)
    bits(rx + 0x08, 8, 5, 0x10)
    bits(rx + 0x0c, 0, 5, 0x10)
    bits(rx + 0x0c, 8, 5, 0x10)
    bits(rx + 0x10, 0, 5, 0x10)
    bits(rx + 0x10, 8, 5, 0x10)
    rmw(rx + 0x0, 0x1 << 21, 0)
    rmw(rx + 0x0, 0x1 << 22, 0)
    rmw(rx + 0x08, 0x1 << 16, 0)
    rmw(rx + 0x08, 0x1 << 17, 0)
    bits(rx + 0x18, 24, 6, 0x0)
    bits(rx + 0x1c, 24, 6, 0x0)
    bits(rx + 0x18, 0, 6, 0x9)
    bits(rx + 0x18, 8, 6, 0x9)
    bits(rx + 0x18, 16, 6, 0x9)
    bits(rx + 0x1c, 0, 6, 0x9)
    bits(rx + 0x1c, 8, 6, 0x9)
    bits(rx + 0x1c, 16, 6, 0x9)
    for lane in range(4):
        wr(dphy + 0x20 + 4 * lane, lane_param())
    rmw(csi2 + 0xE0, 1 << 17, 1 << 17)
    rmw(csi2 + 0x10, 1 << 8, 1 << 8)
    wr(csi2 + 0x0, 0x0); time.sleep(0.002)
    wr(csi2 + 0x0, 0xF)
    rmw(csi2 + 0x4, 0x1, 0x0)
    wr(csi2 + 0x8, 0x0)
    rmw(ctrl + 0x10, 0x1, 0x1)
    rmw(ctrl + 0x0, 0x1, 0x1)
    return ctrl, csi2

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

# analog init on 3 ports
for port, (sidx, rx_off, dphy_off) in {
        '0A': (1, 0x00000, 0x02000),
        '1A': (3, 0x04000, 0x06000),
        '2A': (5, 0x08000, 0x0A000)}.items():
    setup_port(sidx, rx_off, dphy_off)
    print("port %s analog+digital init done (seninf%d)" % (port, sidx), flush=True)

# scan all 5 digital csi2 blocks for data
print("--- scan 5 seninf csi2 blocks ---", flush=True)
for i in range(5):
    c2 = IF_BASE + 0xA00 + 0x1000 * i
    wr(c2 + 0x0, 0x0); time.sleep(0.002)
    wr(c2 + 0x0, 0xF)
    time.sleep(0.6)
    pkt = rd(c2 + 0xD4); cnt = rd(c2 + 0xDC); irq = rd(c2 + 0xC8)
    time.sleep(0.6)
    cnt2 = rd(c2 + 0xDC); irq2 = rd(c2 + 0xC8)
    fr = rd(c2 + 0xD0); dbg = rd(c2 + 0xF4)
    fsm_c = rd(ANA_BASE + (0x02000 if i == 0 else 0x06000 if i == 2 else 0x0A000 if i == 4 else 0) + 0x30)
    fsm_d = rd(ANA_BASE + (0x02000 if i == 0 else 0x06000 if i == 2 else 0x0A000 if i == 4 else 0) + 0x34)
    act = '<<<DATA' if (cnt2 != cnt or pkt or irq2) else ''
    print("intf%d: EN=%08x PKT=%08x CNT=%08x->%08x IRQ=%08x->%08x FR=%08x DBG=%08x clkFSM=%08x dataFSM=%08x %s" %
          (i, rd(c2+0x0), pkt, cnt, cnt2, irq, irq2, fr, dbg, fsm_c, fsm_d, act), flush=True)
    wr(c2 + 0x0, 0x0)
print("done", flush=True)
