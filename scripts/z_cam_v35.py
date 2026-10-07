#!/usr/bin/env python3
# z_cam_v35.py - power chain audit: fan53870 full dump + rt5133 + GPIOs
import subprocess, base64, time

probe = r'''
import subprocess, time, os, mmap, struct
def i2c_r(bus, addr, reg, n=1):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w2@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'r%d'%n], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR:'+str(e)

def i2c_w(bus, addr, reg, val):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w3@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'%02x'%val], capture_output=True, text=True, timeout=8)
        return o.returncode
    except Exception as e: return -1

# fan53870 @ i2c-11 0x35 : dump LDO enable/voltage regs
print('=== fan53870 (i2c-11 0x35) ===')
for r in (0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f,0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f):
    print('0x%02x=%-6s' % (r, i2c_r('11',0x35,r)), end=' ')
    if r % 8 == 7: print()
print()

# rt5133? try i2c-11 scan-lite common addrs
print('=== rt5133 scan ===')
for a in (0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6a,0x6b,0x2c,0x2d,0x2e,0x2f,0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3a,0x3b,0x3c,0x3d,0x3e,0x3f,0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4a,0x4b,0x4c,0x4d,0x4e,0x4f,0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57):
    o = subprocess.run(['i2ctransfer','-f','-y','11','w1@0x%02x'%a,'0x00','r1'], capture_output=True, text=True, timeout=5)
    if o.returncode == 0 and 'error' not in o.stdout.lower():
        print('ack @0x%02x: %s' % (a, o.stdout.strip()))

# try enabling fan53870 LDO6/7 (2.8V AVDD/AFVDD) + LDO5 (IOVDD)
print('=== try fan53870 write 0x03=0x60 ===')
print('rc=%d' % i2c_w('11',0x35,0x03,0x60))
print('0x03 now=%s' % i2c_r('11',0x35,0x03))

# GPIO state
print('=== GPIOs ===')
for g in (152,155,158,164):
    o = subprocess.run(['/root/gpiotool',str(g),'get'], capture_output=True, text=True, timeout=5)
    print('gpio%d: %s' % (g, o.stdout.strip().splitlines()[-1] if o.stdout.strip() else 'ERR'))
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v35.py && python3 /tmp/v35.py"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
