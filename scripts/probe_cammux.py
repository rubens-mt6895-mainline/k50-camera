#!/usr/bin/env python3
# probe_cammux.py - dump 0x1A010000 region to find cammux
import mmap, os, struct

f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
def rd(addr):
    pg = addr & ~0xfff
    m = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
    return struct.unpack_from('<I', m, addr & 0xfff)[0]
def wr(addr, val):
    pg = addr & ~0xfff
    m = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
    struct.pack_into('<I', m, addr & 0xfff, val)

base = 0x1A010000
print("== top region dump (0x1A010000-0x1A0102FC) ==")
for off in range(0, 0x300, 0x10):
    print("+%03x: %s" % (off, " ".join("%08x" % rd(base+off+i) for i in range(0, 0x10, 4))))

print("== 0x1A010300-0x1A0104FF ==")
for off in range(0x300, 0x500, 0x10):
    print("+%03x: %s" % (off, " ".join("%08x" % rd(base+off+i) for i in range(0, 0x10, 4))))

print("== write test at 0x1A010400/0x1A010410 ==")
wr(base+0x400, 0x00202000)
print("read back:", hex(rd(base+0x400)))
wr(base+0x410, 0x0000000C)
print("read back:", hex(rd(base+0x410)))
