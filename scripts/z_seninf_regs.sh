#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'python3 << "EOF"
import mmap, struct, os
f = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
base = 0x1A004000
pg = base & ~0xfff
m = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=pg)
for off in (0x0000, 0x0400, 0x0404, 0x0408, 0x040c, 0x0420, 0x0424, 0x0500, 0x0A00, 0x0A04, 0x0A20, 0x0A24, 0x0AC8):
    v = struct.unpack_from("<I", m, off)[0]
    print("0x%04X = 0x%08X" % (off, v))
EOF' > ${K50_REPO}/out/seninf_regs.log 2>/dev/null
echo DONE
