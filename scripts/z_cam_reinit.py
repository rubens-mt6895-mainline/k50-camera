#!/usr/bin/env python3
# z_cam_reinit.py - rerun full vendor sensor init, then check MIPI actually streams
import subprocess, base64, mmap, os, struct, time

# --- step1: push & run cam_init.sh on device
with open(r'${K50_REPO}\scripts\cam_init.sh', 'rb') as f:
    b64 = base64.b64encode(f.read()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {b64} | base64 -d > /tmp/cam_init.sh && sh /tmp/cam_init.sh > /tmp/init_out.txt 2>&1; echo RC=\\$? >> /tmp/init_out.txt"']
ok = False
for a in range(4):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if r.returncode == 0:
        ok = True
        break
    time.sleep(4)
print('init run:', 'OK' if ok else 'FAIL')

# --- step2: sensor + power + MCLK + SoC state script (runs on device)
probe = r'''
import mmap, os, struct, subprocess, time
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_c = {}
def _m(p):
    if p not in _c: _c[p] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=p)
    return _c[p]
def rd(a): return struct.unpack_from('<I', _m(a & ~0xfff), a & 0xfff)[0]
def i2c(bus, addr, reg):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w2@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'r1'], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR'

print('sensor: 0100=%s 0350=%s 3020=%s 0136=%s' % (
    i2c('10',0x10,0x0100), i2c('10',0x10,0x0350), i2c('10',0x10,0x3020), i2c('10',0x10,0x0136)))
print('fan53870: 03=%s 09=%s 0a=%s' % (i2c('11',0x35,0x03), i2c('11',0x35,0x09), i2c('11',0x35,0x0a)))
print('TG3 TM_CLK(0x1A013F10)=%08x TM_CTL(0x1A013F08)=%08x' % (rd(0x1A013F10), rd(0x1A013F08)))
DPHY = 0x11C86000
CSI2 = 0x1A014A00
def snap(tag):
    p1 = rd(CSI2+0xdc); time.sleep(0.4); p2 = rd(CSI2+0xdc)
    print('%s: clkFSM=%08x dataFSM=%08x PKT=%08x->%08x PKT_ST=%08x IRQ_ST=%08x STCHK_L0..3=%08x/%08x/%08x/%08x' % (
        tag, rd(DPHY+0x30), rd(DPHY+0x34), p1, p2, rd(CSI2+0xd4), rd(CSI2+0xc8),
        rd(DPHY+0x270), rd(DPHY+0x274), rd(DPHY+0x278), rd(DPHY+0x27c)))
snap('T0')
time.sleep(1.0)
snap('T1')
'''
pb64 = base64.b64encode(probe.encode()).decode()
cmd2 = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST} "echo {pb64} | base64 -d > /tmp/probe2.py && python3 /tmp/probe2.py 2>&1"']
r2 = subprocess.run(cmd2, capture_output=True, text=True, timeout=120)
print(r2.stdout)
if r2.stderr: print('ERR:', r2.stderr[-300:])
