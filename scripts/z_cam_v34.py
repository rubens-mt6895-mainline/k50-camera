#!/usr/bin/env python3
# z_cam_v34.py - full sensor reset (XSHUTDOWN low->high) + init + stream + FSM
import subprocess, base64, time

probe = r'''
import subprocess, time, mmap, os, struct
def i2c_r(bus, addr, reg):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w2@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'r1'], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR'

# GPIO155 = cam_rst (out hi = sensor running). Full reset: low 15ms -> high.
gp = subprocess.run(['/root/gpiotool','155','0'], capture_output=True, text=True, timeout=8)
print('rst low: %s' % gp.stdout.strip())
time.sleep(0.015)
gp = subprocess.run(['/root/gpiotool','155','1'], capture_output=True, text=True, timeout=8)
print('rst high: %s' % gp.stdout.strip())
time.sleep(0.05)

# MCLK func1 already hw-confirmed; re-assert via pinmux too
P='/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris'
f=open(P+'/pinmux-select','w'); f.write('GPIO152 func1\n'); f.close()

# re-init sensor after reset
r = subprocess.run(['sh','/tmp/cam_init.sh'], capture_output=True, text=True, timeout=60)
print('init rc=%d' % r.returncode)
time.sleep(0.3)

# stream on
print('0100=%s' % i2c_r('10',0x10,0x0100))
v = i2c_r('10',0x10,0x0100)
if v != '0x01':
    subprocess.run(['i2ctransfer','-f','-y','10','w3@0x10','0x01','0x00','0x01'], capture_output=True, timeout=10)
    time.sleep(0.3)
    print('0100 after on=%s' % i2c_r('10',0x10,0x0100))
print('0350=%s' % i2c_r('10',0x10,0x0350))
time.sleep(0.3)

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
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v34.py && python3 /tmp/v34.py"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
