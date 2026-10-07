#!/usr/bin/env python3
# z_cam_v37.py - try 0x0350=1 (MIPI en) + reset + init + FSM
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

# reset sensor
subprocess.run(['/root/gpiotool','155','0'], capture_output=True, timeout=8)
time.sleep(0.02)
subprocess.run(['/root/gpiotool','155','1'], capture_output=True, timeout=8)
time.sleep(0.1)
subprocess.run(['sh','/tmp/cam_init.sh'], capture_output=True, timeout=60)
time.sleep(0.3)

# dump MIPI/PHY regs before
print('before: 0340=%s 0341=%s 0350=%s 0351=%s 0360=%s' % (
    i2c_r('10',0x10,0x0340), i2c_r('10',0x10,0x0341),
    i2c_r('10',0x10,0x0350), i2c_r('10',0x10,0x0351),
    i2c_r('10',0x10,0x0360)))

# try 0x0350=1
print('write 0350=1 rc=%d, read back=%s' % (i2c_w('10',0x10,0x0350,0x01), i2c_r('10',0x10,0x0350)))
time.sleep(0.2)
print('0100=%s 0101=%s' % (i2c_r('10',0x10,0x0100), i2c_r('10',0x10,0x0101)))

# also dump a few more mipi regs
for r in (0x0342,0x0343,0x0344,0x0345,0x0346,0x0347,0x0348,0x0349,0x034a,0x034b,0x034c,0x034d,0x034e,0x034f):
    print('0x%04x=%s' % (r, i2c_r('10',0x10,r)), end=' ')
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
    print('%s: clkFSM=%08x dataFSM=%08x PKT=%08x->%08x PKT_ST=%08x' % (
        tag, rd(DPHY+0x30), rd(DPHY+0x34), p1, p2, rd(CSI2+0xd4)))
for i in range(4):
    snap('S%d' % i)
    time.sleep(1.0)
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v37.py && python3 /tmp/v37.py"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
