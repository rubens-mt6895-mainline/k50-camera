#!/usr/bin/env python3
# z_cam_v27.py - sensor write-back verification + MIPI enable check
import subprocess, base64, time

probe = r'''
import subprocess, time
def i2c_w(reg, val):
    subprocess.run(['i2ctransfer','-f','-y','10','w3@0x10','%02x'%(reg>>8),'%02x'%(reg&0xff),'%02x'%val],
                   capture_output=True, text=True, timeout=8)
def i2c_r(reg):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y','10','w2@0x10',
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'r1'], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR:%s'%e

print('--- stream off ---')
i2c_w(0x0100, 0x00); time.sleep(0.3)
print('0100=%s' % i2c_r(0x0100))

print('--- 0x0350 write-back test ---')
i2c_w(0x0350, 0x01); time.sleep(0.1)
print('0350 after w1 = %s' % i2c_r(0x0350))
i2c_w(0x0350, 0x00); time.sleep(0.1)
print('0350 after w0 = %s' % i2c_r(0x0350))

print('--- streaming-seq regs readback ---')
for reg in (0x3c7e, 0x3c7f, 0x3fe2, 0x3fe3, 0x3fe4, 0x3fe5, 0x3e20, 0x3e3b, 0x4034, 0x4035, 0x3020):
    print('0x%04x = %s' % (reg, i2c_r(reg)))

print('--- frame config ---')
for reg in (0x0340, 0x0341, 0x0342, 0x0343, 0x0344, 0x0345, 0x0346, 0x0347):
    print('0x%04x = %s' % (reg, i2c_r(reg)))

print('--- stream on ---')
i2c_w(0x0100, 0x01); time.sleep(0.5)
print('0100=%s 0350=%s' % (i2c_r(0x0100), i2c_r(0x0350)))
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v27.py && python3 /tmp/v27.py 2>&1"']
for a in range(6):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, flush=True)
    time.sleep(5)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
