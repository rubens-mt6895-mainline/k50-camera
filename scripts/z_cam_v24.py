#!/usr/bin/env python3
# z_cam_v24.py - RESTORE sensor-side chain: MCLK pinmux + fan53870 rails + full init + stream check
import subprocess, base64, time

# ---- stage A: pinmux MCLK + fan rails + init + probe (all on device) ----
script = r'''
set -x
# 1. MCLK pin 152 -> func1 (CMMCLK2), RST pin 155 -> func1
P=$(ls -d /sys/kernel/debug/pinctrl/*pinctrl_paris 2>/dev/null | head -1)
echo "pinctrl dir: $P"
echo "GPIO152 func1" > $P/pinmux-select
echo "GPIO155 func1" > $P/pinmux-select
sleep 0.2
# 2. fan53870 rails: IOUT=0x7f, ENABLE=0x60(LDO6+7), LDO6/7 VOUT=0xB3(2.8V)
i2ctransfer -f -y 11 w2@0x35 0x02 0x7f
i2ctransfer -f -y 11 w2@0x35 0x03 0x60
i2ctransfer -f -y 11 w2@0x35 0x09 0xb3
i2ctransfer -f -y 11 w2@0x35 0x0a 0xb3
sleep 0.3
echo "--- fan readback ---"
for r in 02 03 09 0a; do
  echo "fan[$r]=$(i2ctransfer -f -y 11 w2@0x35 0x$r r1 2>&1 | tr -d '\n')"
done
# 3. pinmux readback
grep -E "pin 152|pin 155" $P/pinmux-pins
# 4. full vendor sensor init
sh /tmp/cam_init.sh 2>/dev/null || { echo "no /tmp/cam_init.sh, pushing needed"; }
echo "--- sensor after init ---"
for r in 0100 0350 3020; do
  echo "sensor[$r]=$(i2ctransfer -f -y 10 w2@0x10 0x$(echo $r|cut -c1-2) 0x$(echo $r|cut -c3-4) r1 2>&1 | tr -d '\n')"
done
'''
s64 = base64.b64encode(script.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {s64} | base64 -d | sh 2>&1"']
ok = False
for a in range(4):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if r.returncode == 0:
        ok = True
        print('STAGE A:')
        print(r.stdout)
        if r.stderr: print('ERR:', r.stderr[-200:])
        break
    time.sleep(4)
if not ok:
    print('STAGE A FAIL', r.stdout[-200:], r.stderr[-200:])

# ---- stage B: FSM/PKT while streaming (python mmap probe) ----
probe = r'''
import mmap, os, struct, time
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
for i in range(3):
    snap('S%d' % i)
    time.sleep(1.0)
'''
pb = base64.b64encode(probe.encode()).decode()
cmd2 = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST} "echo {pb} | base64 -d > /tmp/probe3.py && python3 /tmp/probe3.py 2>&1"']
for a in range(4):
    r2 = subprocess.run(cmd2, capture_output=True, text=True, timeout=120)
    if r2.returncode == 0:
        print('STAGE B:')
        print(r2.stdout)
        if r2.stderr: print('ERR:', r2.stderr[-200:])
        break
    time.sleep(4)
else:
    print('STAGE B FAIL', r2.stdout[-200:], r2.stderr[-200:])
