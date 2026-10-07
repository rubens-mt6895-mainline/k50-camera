#!/usr/bin/env python3
# diff seninf map regions streaming off/on
import mmap, os, struct, time, subprocess

f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_cache = {}
def rd(addr):
    pg = addr & ~0xfff
    if pg not in _cache: _cache[pg] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
    return struct.unpack_from('<I', _cache[pg], addr & 0xfff)[0]
def i2c(*args):
    return subprocess.run(['i2ctransfer', '-f', '-y', *args], capture_output=True, text=True).stdout.strip()

REGIONS = [("seninf_map", 0x1A004000, 0xA000), ("seninf_top", 0x1A010000, 0x20000)]

i2c('10','w3@0x10','0x01','0x00','0x00')
time.sleep(0.5)
def snap():
    out = {}
    for label, base, size in REGIONS:
        for off in range(0, size, 4):
            v = rd(base + off)
            if v: out[(label, off)] = v
    return out
off_map = snap()
i2c('10','w3@0x10','0x01','0x00','0x01')
time.sleep(1.0)
on_map = snap()
print("off:", len(off_map), "on:", len(on_map), flush=True)
diffs = [k for k in set(off_map)|set(on_map) if off_map.get(k,0)!=on_map.get(k,0)]
print("--- diffs ---", flush=True)
for (label, off), v in sorted([(k, on_map.get(k,0)) for k in diffs], key=lambda x:(x[0][0],x[0][1])):
    a = off_map.get((label,off), 0)
    print("  %s +%05x: %08x -> %08x" % (label, off, a, v), flush=True)
print("total:", len(diffs), flush=True)
