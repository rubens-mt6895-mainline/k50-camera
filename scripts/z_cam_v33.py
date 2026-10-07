#!/usr/bin/env python3
# z_cam_v33.py - hardware-level GPIO152 MODE read/write + FSM check
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

GPIO152_MODE = 0x10005430  # GPIO_BASE 0x10005000 + 0x300 + (152/8=19)*0x10, bit0-3
v = rd(GPIO152_MODE)
print('GPIO152 MODE (0x10005430) before = 0x%08x, mode=%d' % (v, v & 0xF))
if (v & 0xF) != 1:
    wr(GPIO152_MODE, (v & ~0xF) | 0x1)
    time.sleep(0.1)
    v2 = rd(GPIO152_MODE)
    print('after write = 0x%08x, mode=%d' % (v2, v2 & 0xF))
else:
    print('already func1')

# also read clk regs for camtg3 mclk out path
CLK = 0x1A000000  # camsys? actually cam_m gate
for a in (0x1A013F10, 0x1A013F14, 0x1A013F00):
    print('clk @0x%08x = 0x%08x' % (a, rd(a)))

# sensor streaming state
print('0100=%s 0350=%s' % (i2c_r('10',0x10,0x0100), i2c_r('10',0x10,0x0350)))

DPHY = 0x11C86000; CSI2 = 0x1A014A00
def snap(tag):
    p1 = rd(CSI2+0xdc); time.sleep(0.4); p2 = rd(CSI2+0xdc)
    print('%s: clkFSM=%08x dataFSM=%08x PKT=%08x->%08x' % (tag, rd(DPHY+0x30), rd(DPHY+0x34), p1, p2))
for i in range(4):
    snap('S%d' % i)
    time.sleep(1.0)
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v33.py && python3 /tmp/v33.py"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
