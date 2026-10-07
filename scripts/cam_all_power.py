#!/usr/bin/env python3
# cam_all_power.py - power up full chain: MM_INFRA -> ISP_VCORE -> CAM_VCORE -> CAM_MAIN (+ISP_MAIN already)
# SPM base 0x1c001000; ctl offsets from mtk-scpsys-mt6895.c
import mmap, os, struct, time

SPM = 0x1c001000
DOMAINS = [  # (name, ctl_offs)
    ("mm_infra",  0xE6C),
    ("isp_vcore", 0xE30),
    ("cam_vcore", 0xE58),
    ("cam_main",  0xE44),
    ("isp_main",  0xE24),
]
PWR_ON = 1 << 2
PWR_ON2 = 1 << 3
CLK_DIS = 1 << 4
ISO = 1 << 1
RST_B = 1 << 0
SRAM_PDN = 1 << 8
SRAM_ACK = 1 << 12
STA_MASK = 0xC0000000

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

def power_up(name, ctl):
    c = SPM + ctl
    print("--- %s: PWR_CON=%08x ---" % (name, rd(c)), flush=True)
    if (rd(c) & STA_MASK) == STA_MASK and not (rd(c) & CLK_DIS):
        print("  already up", flush=True)
        return True
    v = rd(c) | PWR_ON
    wr(c, v)
    v |= PWR_ON2
    wr(c, v)
    ok = False
    for i in range(200):
        if (rd(c) & STA_MASK) == STA_MASK:
            print("  PWR_ON ack @%d" % i, flush=True)
            ok = True
            break
        time.sleep(0.01)
    if not ok:
        print("  TIMEOUT PWR_ON, PWR_CON=%08x" % rd(c), flush=True)
    v = rd(c) & ~CLK_DIS
    wr(c, v)
    v &= ~ISO
    wr(c, v)
    v |= RST_B
    wr(c, v)
    v &= ~SRAM_PDN
    wr(c, v)
    for i in range(100):
        if rd(c) & SRAM_ACK:
            print("  SRAM up ack @%d" % i, flush=True)
            break
        time.sleep(0.01)
    print("  final PWR_CON=%08x" % rd(c), flush=True)
    return ok

print("=== powering up dependency chain ===", flush=True)
for name, ctl in DOMAINS:
    power_up(name, ctl)

print("=== seninf check ===", flush=True)
print("1A010000: %08x" % rd(0x1A010000), flush=True)
