#!/usr/bin/env python3
# z_cam_v26.py - FIX LANE_SELECT to vendor golden 0x80413002 (was 0x80403102)
import subprocess, base64, time

probe = r'''
import mmap, os, struct, subprocess, time
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_c = {}
def _m(p):
    if p not in _c: _c[p] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=p)
    return _c[p]
def rd(a): return struct.unpack_from('<I', _m(a & ~0xfff), a & 0xfff)[0]
def wr(a, v): struct.pack_into('<I', _m(a & ~0xfff), a & 0xfff, v)
DPHY = 0x11C86000; CSI2 = 0x1A014A00; ANAA = 0x11C84000; ANAB = 0x11C85000

# stop streaming
subprocess.run(['i2ctransfer','-f','-y','10','w3@0x10','0x01','0x00','0x00'], capture_output=True)
time.sleep(0.3)

# FIX: vendor golden LANE_SELECT
wr(DPHY+0x04, 0x80413002)
print('LANE_SELECT=%08x (vendor golden 0x80413002)' % rd(DPHY+0x04))

# keep EN/SPARE
wr(DPHY+0x00, 0x0F01)
wr(DPHY+0xf0, 0xf1)
# restart streaming
subprocess.run(['i2ctransfer','-f','-y','10','w3@0x10','0x01','0x00','0x01'], capture_output=True)
time.sleep(0.5)

def snap(tag):
    p1 = rd(CSI2+0xdc); time.sleep(0.4); p2 = rd(CSI2+0xdc)
    print('%s: clkFSM=%08x dataFSM=%08x PKT=%08x->%08x PKT_ST=%08x IRQ=%08x GEN=%08x' % (
        tag, rd(DPHY+0x30), rd(DPHY+0x34), p1, p2, rd(CSI2+0xd4), rd(CSI2+0xc8), rd(CSI2+0xd8)))
    print('   STCHK L0=%08x L1=%08x L2=%08x L3=%08x' % (
        rd(DPHY+0x270), rd(DPHY+0x274), rd(DPHY+0x278), rd(DPHY+0x27c)))
for i in range(3):
    snap('S%d' % i)
    time.sleep(1.0)
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v26.py && python3 /tmp/v26.py 2>&1"']
for a in range(6):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(5)
else:
    print('FAIL', r.stdout[-200:], r.stderr[-200:])
