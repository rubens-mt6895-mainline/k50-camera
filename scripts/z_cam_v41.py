#!/usr/bin/env python3
# z_cam_v41.py - THE FIX: main cam MCLK = CMMCLK3 = GPIO162 (not 152!)
import subprocess, base64, time

probe = r'''
import subprocess, time, mmap, os, struct
def i2c_r(bus, addr, reg):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w2@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'r1'], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR'

f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_c = {}
def _m(p):
    if p not in _c: _c[p] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=p)
    return _c[p]
def rd(a): return struct.unpack_from('<I', _m(a & ~0xfff), a & 0xfff)[0]
def wr(a, v): struct.pack_into('<I', _m(a & ~0xfff), a & 0xfff, v)

P='/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris'
def mode_addr(pin): return 0x10005000 + 0x300 + (pin//8)*0x10

# check MODE of 150/151/152/162
for pin in (150,151,152,162):
    print('GPIO%d MODE=0x%08x -> mode %d' % (pin, rd(mode_addr(pin)), rd(mode_addr(pin)) & 0xF))

# set GPIO162 func1 (CMMCLK3) via pinmux-select AND hw
f2=open(P+'/pinmux-select','w'); f2.write('GPIO162 func1\n'); f2.close()
v = rd(mode_addr(162))
if (v & 0xF) != 1:
    wr(mode_addr(162), (v & ~0xF) | 1)
print('GPIO162 after set: mode=%d' % (rd(mode_addr(162)) & 0xF))
# release 152 back to func0
f2=open(P+'/pinmux-select','w'); f2.write('GPIO152 func0\n'); f2.close()
print('GPIO152 now mode=%d' % (rd(mode_addr(152)) & 0xF))

# reset sensor + init + stream
subprocess.run(['/root/gpiotool','155','0'], capture_output=True, timeout=8)
time.sleep(0.02)
subprocess.run(['/root/gpiotool','155','1'], capture_output=True, timeout=8)
time.sleep(0.15)
r = subprocess.run(['sh','/tmp/cam_init.sh'], capture_output=True, text=True, timeout=60)
print('init rc=%d' % r.returncode)
time.sleep(0.3)
print('0100=%s' % i2c_r('10',0x10,0x0100))

DPHY = 0x11C86000; CSI2 = 0x1A014A00
def snap(tag):
    p1 = rd(CSI2+0xdc); time.sleep(0.4); p2 = rd(CSI2+0xdc)
    print('%s: clkFSM=%08x dataFSM=%08x PKT=%08x->%08x PKT_ST=%08x IRQ=%08x GEN=%08x' % (
        tag, rd(DPHY+0x30), rd(DPHY+0x34), p1, p2, rd(CSI2+0xd4), rd(CSI2+0xc8), rd(CSI2+0xd8)))
for i in range(5):
    snap('S%d' % i)
    time.sleep(1.0)
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v41.py && python3 /tmp/v41.py"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
