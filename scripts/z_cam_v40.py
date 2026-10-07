#!/usr/bin/env python3
# z_cam_v40.py - IMX582 proper sequence: reset, 0x0100=0, init, 0x0100=0/1, PHY check, FSM
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
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w3@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'%02x'%val], capture_output=True, text=True, timeout=8)
        return o.returncode
    except Exception as e: return -1

# 1. reset
subprocess.run(['/root/gpiotool','155','0'], capture_output=True, timeout=8)
time.sleep(0.02)
subprocess.run(['/root/gpiotool','155','1'], capture_output=True, timeout=8)
time.sleep(0.15)
print('after reset: 0x0005=%s 0x0006=%s' % (i2c_r('10',0x10,0x0005), i2c_r('10',0x10,0x0006)))

# 2. stream off + hold release (0x0100=0, 0x0101=0)
i2c_w('10',0x10,0x0100,0x00)
i2c_w('10',0x10,0x0101,0x00)
time.sleep(0.05)

# 3. init
r = subprocess.run(['sh','/tmp/cam_init.sh'], capture_output=True, text=True, timeout=60)
print('init rc=%d' % r.returncode)
time.sleep(0.2)

# 4. ensure stream on
print('0100=%s 0101=%s' % (i2c_r('10',0x10,0x0100), i2c_r('10',0x10,0x0101)))
i2c_w('10',0x10,0x0100,0x01)
time.sleep(0.5)
print('0100 after=%s' % i2c_r('10',0x10,0x0100))

# 5. PHY regs
print('PHY: 0340=%s 0350=%s 0360=%s 0301=%s 0311=%s 0316=%s' % (
    i2c_r('10',0x10,0x0340), i2c_r('10',0x10,0x0350), i2c_r('10',0x10,0x0360),
    i2c_r('10',0x10,0x0301), i2c_r('10',0x10,0x0311), i2c_r('10',0x10,0x0316)))
# PLL-ish status regs
for rr in (0x5a00,0x5a01,0x5a02,0x5a03,0x5b00,0x5b01):
    v = i2c_r('10',0x10,rr)
    if v != '0x00' and v != 'ERR': print('0x%04x=%s' % (rr, v), end=' ')
print()

f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_c = {}
def _m(p):
    if p not in _c: _c[p] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=p)
    return _c[p]
def rd(a): return struct.unpack_from('<I', _m(a & ~0xfff), a & 0xfff)[0]
DPHY = 0x11C86000; CSI2 = 0x1A014A00
def snap(tag):
    p1 = rd(CSI2+0xdc); time.sleep(0.4); p2 = rd(CSI2+0xdc)
    print('%s: clkFSM=%08x dataFSM=%08x PKT=%08x->%08x PKT_ST=%08x IRQ=%08x' % (
        tag, rd(DPHY+0x30), rd(DPHY+0x34), p1, p2, rd(CSI2+0xd4), rd(CSI2+0xc8)))
for i in range(5):
    snap('S%d' % i)
    time.sleep(1.0)
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v40.py && python3 /tmp/v40.py"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
