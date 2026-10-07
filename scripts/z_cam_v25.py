#!/usr/bin/env python3
# z_cam_v25.py - BIST self-test to isolate PHY->CSI2 path + full status
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
DPHY = 0x11C86000; CSI2 = 0x1A014A00
def i2c(reg):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y','10','w2@0x10',
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'r1'], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR'

# stop sensor streaming first (avoid BIST conflict)
subprocess.run(['i2ctransfer','-f','-y','10','w3@0x10','0x01','0x00','0x00'], capture_output=True)
time.sleep(0.3)
print('sensor stream=0, 0x0350=%s' % i2c(0x0350))

print('=== DPHY status before BIST ===')
for off, nm in [(0xa0,'STATUS_0'),(0xa4,'STATUS_1'),(0x8c,'IRQ_STATUS'),(0x8,'HS_RX_EN_SW'),
                (0x260,'STATE_CHK_EN'),(0x270,'ST_L0'),(0x274,'ST_L1'),(0x278,'ST_L2'),(0x27c,'ST_L3')]:
    print('  +%03x %-11s = %08x' % (off, nm, rd(DPHY+off)))

print('=== BIST run ===')
wr(DPHY+0x100, 0xf)   # BIST enable 4 lanes
time.sleep(0.3)
print('BIST_STATUS=%08x' % rd(DPHY+0x104))
p1 = rd(CSI2+0xdc); time.sleep(0.3); p2 = rd(CSI2+0xdc)
print('PKT during BIST: %08x->%08x %s' % (p1, p2, '<<< PACKETS!' if p1 != p2 else 'static'))
print('CSI2 PKT_ST=%08x IRQ_ST=%08x' % (rd(CSI2+0xd4), rd(CSI2+0xc8)))
print('BIST_STATUS2=%08x' % rd(DPHY+0x104))
wr(DPHY+0x100, 0)    # BIST off
time.sleep(0.1)
print('BIST off, BIST_STATUS=%08x' % rd(DPHY+0x104))

# restart sensor streaming
subprocess.run(['i2ctransfer','-f','-y','10','w3@0x10','0x01','0x00','0x01'], capture_output=True)
time.sleep(0.3)
print('=== streaming restored ===')
print('clkFSM=%08x dataFSM=%08x' % (rd(DPHY+0x30), rd(DPHY+0x34)))
for off, nm in [(0xa0,'STATUS_0'),(0xa4,'STATUS_1'),(0x8c,'IRQ_STATUS')]:
    print('  +%03x %-11s = %08x' % (off, nm, rd(DPHY+off)))
p1 = rd(CSI2+0xdc); time.sleep(0.4); p2 = rd(CSI2+0xdc)
print('PKT stream: %08x->%08x' % (p1, p2))
print('CSI2 PKT_ST=%08x GEN_SHORT=%08x' % (rd(CSI2+0xd4), rd(CSI2+0xd8)))
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v25.py && python3 /tmp/v25.py 2>&1"']
for a in range(8):
    print('attempt', a, flush=True)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=150)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        if r.stderr: print('ERR:', r.stderr[-300:])
        break
    print('  rc=%d out=%r err=%r' % (r.returncode, r.stdout[-80:], r.stderr[-80:]), flush=True)
    time.sleep(5)
else:
    print('FAIL after retries')
