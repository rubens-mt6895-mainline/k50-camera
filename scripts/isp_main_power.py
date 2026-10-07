#!/usr/bin/env python3
# isp_main_power.py - manually power up MT6895 ISP_MAIN domain via SPM PWR_CON
# SPM base = 0x1c001000, ISP_MAIN ctl_offs = 0xE24
import mmap, os, struct, time

SPM = 0x1c001000
CTL = SPM + 0xE24
PWR_STA = SPM + 0x60C
PWR_ON = 1 << 2
PWR_ON2 = 1 << 3
CLK_DIS = 1 << 4
ISO = 1 << 1
RST_B = 1 << 0
SRAM_PDN = 1 << 8
SRAM_ACK = 1 << 12
STA_MASK = 0xC0000000  # GENMASK(31,30)

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

print("before: PWR_CON=%08x PWR_STATUS=%08x" % (rd(CTL), rd(PWR_STA)), flush=True)

# 1. PWR_ON
val = rd(CTL)
val |= PWR_ON
wr(CTL, val)
val |= PWR_ON2
wr(CTL, val)

# 2. wait ack
for i in range(100):
    st = rd(CTL) & STA_MASK
    if st == STA_MASK:
        print("PWR_CON on-ack at %d: %08x" % (i, rd(CTL)), flush=True)
        break
    time.sleep(0.01)
else:
    print("TIMEOUT waiting PWR_ON ack, CTL=%08x STA=%08x" % (rd(CTL), st), flush=True)

time.sleep(0.0001)
# 3. clk dis off, iso off, rst release
val = rd(CTL)
val &= ~CLK_DIS
wr(CTL, val)
val &= ~ISO
wr(CTL, val)
val |= RST_B
wr(CTL, val)

# 4. sram pdn off (power up)
val = rd(CTL)
val &= ~SRAM_PDN
wr(CTL, val)
for i in range(50):
    if rd(CTL) & SRAM_ACK:
        print("SRAM up ack at %d" % i, flush=True)
        break
    time.sleep(0.01)
else:
    print("SRAM ack timeout, CTL=%08x" % rd(CTL), flush=True)

print("after:  PWR_CON=%08x PWR_STATUS=%08x" % (rd(CTL), rd(PWR_STA)), flush=True)
