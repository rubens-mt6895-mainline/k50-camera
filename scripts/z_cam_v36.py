#!/usr/bin/env python3
# z_cam_v36.py - GPIO level check + fan53870 8-bit addr retry
import subprocess, base64, time

probe = r'''
import subprocess, time
print('=== debugfs gpio 150-170 ===')
o = subprocess.run(['sh','-c','grep -E "gpio-(150|151|152|153|154|155|156|157|158|159|160|161|162|163|164|165)" /sys/kernel/debug/gpio'], capture_output=True, text=True, timeout=8)
print(o.stdout)
print('=== gpiotool help ===')
o = subprocess.run(['/root/gpiotool'], capture_output=True, text=True, timeout=8)
print(o.stdout[:500])

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
print('=== fan53870 0x35: 16-bit vs 8-bit addr ===')
for r in (0x00,0x03,0x09,0x0a,0x1a):
    print('r%02x: w2=%s w1=%s' % (r, i2c_r16('11',0x35,r), i2c_r8('11',0x35,r)))
print('=== rt5133 0x66 ===')
for r in (0x00,0x01,0x02,0x03,0x05,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x10,0x11,0x12,0x13):
    print('r%02x=%s' % (r, i2c_r8('11',0x66,r)))
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v36.py && python3 /tmp/v36.py"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
