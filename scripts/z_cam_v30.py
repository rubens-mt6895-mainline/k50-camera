#!/usr/bin/env python3
# z_cam_v30.py - re-assert MCLK func1 + full init + verify MIPI streaming end-to-end
import subprocess, base64, time

probe = r'''
import subprocess, time, mmap, os, struct
def i2c_r(bus, addr, reg):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w2@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'r1'], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR'
def i2c_w(bus, addr, reg, val):
    subprocess.run(['i2ctransfer','-f','-y',bus,'w3@0x%02x'%addr,
        '%02x'%(reg>>8),'%02x'%(reg&0xff),'%02x'%val], capture_output=True, timeout=8)

# 1. MCLK pin152 -> func1 (ONLY 152, never touch 155)
P = None
for d in os.listdir('/sys/kernel/debug/pinctrl'):
    if 'pinctrl_paris' in d: P = '/sys/kernel/debug/pinctrl/' + d
print('pinctrl:', P)
open(P + '/pinmux-select','w').write('GPIO152 func1')
time.sleep(0.2)
print('152:', [l.strip() for l in open(P + '/pinmux-pins') if 'pin 152' in l])
print('155:', [l.strip() for l in open(P + '/pinmux-pins') if 'pin 155' in l])

# 2. sensor state before init
print('pre: 0100=%s 0350=%s' % (i2c_r('10',0x10,0x0100), i2c_r('10',0x10,0x0350)))

# 3. full init (cam_init.sh already at /tmp)
r = subprocess.run(['sh','/tmp/cam_init.sh'], capture_output=True, text=True, timeout=60)
print('cam_init rc=%d tail=%s' % (r.returncode, r.stdout[-40:]))
time.sleep(0.5)

# 4. sensor after init
print('post: 0100=%s 0350=%s 3020=%s 3c7e=%s 3c7f=%s' % (
    i2c_r('10',0x10,0x0100), i2c_r('10',0x10,0x0350), i2c_r('10',0x10,0x3020),
    i2c_r('10',0x10,0x3c7e), i2c_r('10',0x10,0x3c7f)))

# 5. ensure streaming on
i2c_w('10',0x10,0x0100,0x01)
time.sleep(0.5)

# 6. SoC FSM/PKT
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_c = {}
def _m(p):
    if p not in _c: _c[p] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=p)
    return _c[p]
def rd(a): return struct.unpack_from('<I', _m(a & ~0xfff), a & 0xfff)[0]
DPHY = 0x11C86000; CSI2 = 0x1A014A00
def snap(tag):
    p1 = rd(CSI2+0xdc); time.sleep(0.4); p2 = rd(CSI2+0xdc)
    print('%s: clkFSM=%08x dataFSM=%08x PKT=%08x->%08x PKT_ST=%08x IRQ=%08x GEN=%08x' % (
        tag, rd(DPHY+0x30), rd(DPHY+0x34), p1, p2, rd(CSI2+0xd4), rd(CSI2+0xc8), rd(CSI2+0xd8)))
for i in range(4):
    snap('S%d' % i)
    time.sleep(1.0)
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v30.py && python3 /tmp/v30.py 2>&1"']
for a in range(6):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(5)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
