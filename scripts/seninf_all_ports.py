#!/usr/bin/env python3
# seninf_all_ports.py - init ALL 8 ana ports (ISP7.1 style) + enable all CSI2 digital
# then diff streaming off/on to find ANY port with MIPI activity.
import mmap, os, struct, time, subprocess

ANA = 0x11c80000
SENINF = 0x1a010000
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_cache = {}
def rd(addr):
    pg = addr & ~0xfff
    if pg not in _cache: _cache[pg] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
    return struct.unpack_from('<I', _cache[pg], addr & 0xfff)[0]
def wr(addr, val):
    pg = addr & ~0xfff
    if pg not in _cache: _cache[pg] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
    struct.pack_into('<I', _cache[pg], addr & 0xfff, val)

def i2c(*args):
    r = subprocess.run(['i2ctransfer', '-f', '-y', *args], capture_output=True, text=True)
    return r.stdout.strip()

def mset(addr, mask, val):
    v = rd(addr)
    v = (v & ~mask) | (val & mask)
    wr(addr, v)

# ---- phyA init (ISP7.1 sequence, per port stride 0x4000) ----
def phyA_power_on(rxbase):
    wr(rxbase + 0x00, rd(rxbase + 0x00) | 0x1)          # BG_CORE_EN
    wr(rxbase + 0x04, rd(rxbase + 0x04) | 0x80000000)   # XTAL ready?
    time.sleep(0.01)
    wr(rxbase + 0x0f4, 0x00530200)                      # phyA_csi0a_1 (mode)
    wr(rxbase + 0x0f0, 0x000200e2)                      # csi0a_0

def dphy_init(dbase, lanes=4):
    # lane enable: each lane top
    for i in range(4):
        wr(dbase + 0x10 + i*4, 0x10000000)   # clk lane
    for i in range(4):
        wr(dbase + 0x20 + i*4, 0x30103402)   # data lane params
    mset(dbase + 0x30, 0xFFFFFFFF, 0x00000101)  # clk FSM ctrl
    mset(dbase + 0x34, 0xFFFFFFFF, 0x80808080)  # data FSM ctrl

def enable_csi2(pidx):
    b = SENINF + 0x200 + pidx*0x2000
    mset(b + 0x800, 0xFFFFFFFF, 0x0000000F)  # CSI2_EN lanes

print("=== init all ana ports ===", flush=True)
for i in range(8):
    rx = ANA + i*0x4000
    dy = ANA + i*0x4000 + 0x2000
    phyA_power_on(rx)
    dphy_init(dy)
    print("port %d: rx=%08x dphy=%08x" % (i, rx, dy), flush=True)
print("=== enable all CSI2 digital ===", flush=True)
for i in range(10):
    b = SENINF + 0x200 + i*0x2000
    mset(b + 0x800, 0xFFFFFFFF, 0x0000000F)
print("done init", flush=True)

# ---- streaming off ----
i2c('10','w3@0x10','0x01','0x00','0x00')
time.sleep(0.6)
def snap():
    out = {}
    for off in range(0, 0x20000, 4):
        v = rd(ANA + off)
        if v: out[off] = v
    return out
off_map = snap()
print("off nonzero:", len(off_map), flush=True)

i2c('10','w3@0x10','0x01','0x00','0x01')
time.sleep(1.0)
on_map = snap()
print("on nonzero:", len(on_map), flush=True)

diffs = [(o, off_map.get(o,0), on_map.get(o,0)) for o in sorted(set(off_map)|set(on_map)) if off_map.get(o,0)!=on_map.get(o,0)]
print("--- diffs ---", flush=True)
for off, a, b in diffs:
    blk = "p%d%s" % ((off//0x4000), "rx" if (off%0x4000)<0x2000 else "dp")
    print("  %s +%05x: %08x -> %08x" % (blk, off, a, b), flush=True)
print("total diffs:", len(diffs), flush=True)
# keep streaming
i2c('10','w3@0x10','0x01','0x00','0x01')
print("done", flush=True)
