#!/usr/bin/env python3
# z_cam_v38.py - sensor power domain audit: temp + reg partition + fan53870 8-bit volt write
import subprocess, base64, time

probe = r'''
import subprocess, time
def i2c_r16(bus, addr, reg):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w2@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'r1'], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR'
def i2c_r8(bus, addr, reg):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w1@0x%02x'%addr,
            '%02x'%reg,'r1'], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR'
def i2c_w8(bus, addr, reg, val):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w2@0x%02x'%addr,
            '%02x'%reg,'%02x'%val], capture_output=True, text=True, timeout=8)
        return o.returncode
    except Exception as e: return -1

print('=== IMX582 reg partition (bus10 0x10) ===')
# core regs (IOVDD domain)
for r in (0x0000,0x0001,0x0002,0x0003,0x0005,0x0006,0x0009,0x000a,0x000b,0x0010,0x0011,0x0014,0x0015,0x0016,0x0017,0x0020,0x0021,0x0022,0x0023,0x0024,0x0025,0x0026,0x0027,0x0028,0x0029,0x002a,0x002b,0x002c,0x002d,0x002e,0x002f):
    print('0x%04x=%s' % (r, i2c_r16('10',0x10,r)), end=' ')
    if r % 8 == 7: print()
print()
# temp
print('temp 0x0138=%s 0x0139=%s' % (i2c_r16('10',0x10,0x0138), i2c_r16('10',0x10,0x0139)))
# PHY partition sweep
print('=== PHY regs 0x0300-0x0370 ===')
for r in range(0x0300,0x0371):
    v = i2c_r16('10',0x10,r)
    if v and v != '0x00':
        print('0x%04x=%s' % (r, v), end=' ')
print()
print('=== PHY regs 0x0380-0x03ff ===')
for r in range(0x0380,0x0400):
    v = i2c_r16('10',0x10,r)
    if v and v != '0x00':
        print('0x%04x=%s' % (r, v), end=' ')
print()

print('=== fan53870 8-bit voltage write ===')
print('0x03 before=%s' % i2c_r8('11',0x35,0x03))
for r in (0x09,0x0a):
    print('write 0x%02x=0xb3 rc=%d read=%s' % (r, i2c_w8('11',0x35,r,0xb3), i2c_r8('11',0x35,r)))
print('0x03 after=%s' % i2c_r8('11',0x35,0x03))
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v38.py && python3 /tmp/v38.py"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
