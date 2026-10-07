#!/usr/bin/env python3
# z_cam_v39.py - hard check TOP CLK_CFG_5 pdn for camtg3_sel; clear if needed
import subprocess, base64, time

probe = r'''
import subprocess, time, mmap, os, struct
f = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
_c = {}
def _m(p):
    if p not in _c: _c[p] = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, offset=p)
    return _c[p]
def rd(a): return struct.unpack_from('<I', _m(a & ~0xfff), a & 0xfff)[0]
def wr(a, v): struct.pack_into('<I', _m(a & ~0xfff), a & 0xfff, v)

TOP = 0x10000000
def r(o): return rd(TOP + o)
def w(o, v): wr(TOP + o, v)

print('CLK_CFG_5   (0x60) = 0x%08x  camtg3_sel[mux=%d] pdn31=%d' % (r(0x60), (r(0x60)>>24)&0xF, (r(0x60)>>31)&1))
print('CLK_CFG_5_SET(0x64) = 0x%08x' % r(0x64))
print('CLK_CFG_5_CLR(0x68) = 0x%08x' % r(0x68))
print('CLK_CFG_UPDATE (0x4) = 0x%08x' % r(0x4))

# if pdn31=1 (gated), open the gate: write SET reg bit31 (gate off = set pdn->0 via SET? in MTK CLR_SET_UPD: SET reg bit = set value 1 -> pdn? check)
# MUX_GATE_CLR_SET_UPD: gate clear/set scheme: enable -> write SET bit (bit31) to clear pdn. We'll write bit31=1 in SET reg then pulse UPDATE.
if (r(0x60)>>31)&1:
    w(0x64, 1<<31)   # SET reg bit31 = enable gate (clear pdn)
    w(0x4, 1<<23)    # TOP_MUX_CAMTG3_SHIFT (from header) - need actual shift
    time.sleep(0.01)
    print('after SET: CLK_CFG_5 = 0x%08x pdn31=%d' % (r(0x60), (r(0x60)>>31)&1))

# try to find TOP_MUX_CAMTG3_SHIFT
print('UPDATE reg after pulse = 0x%08x' % r(0x4))
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v39.py && python3 /tmp/v39.py"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
