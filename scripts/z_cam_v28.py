#!/usr/bin/env python3
# z_cam_v28.py - restore camera rails: fan53870 full LDO reconfigure + sensor revive + init
import subprocess, base64, time

probe = r'''
import subprocess, time
def i2c(bus, addr, reg, rlen=1):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w2@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'r%d'%rlen], capture_output=True, text=True, timeout=8)
        return o.stdout.strip()
    except Exception as e: return 'ERR'
def i2cw(bus, addr, reg, val):
    try:
        o = subprocess.run(['i2ctransfer','-f','-y',bus,'w3@0x%02x'%addr,
            '%02x'%(reg>>8),'%02x'%(reg&0xff),'%02x'%val], capture_output=True, text=True, timeout=8)
        return o.returncode
    except Exception as e: return 'ERR'

print('--- fan53870 before ---')
for r in (0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x09,0x0a):
    print('fan[%02x]=%s' % (r, i2c('11',0x35,r)))

print('--- reconfigure fan53870 (datasheet values) ---')
for r in range(0x00, 0x07):
    i2cw('11',0x35,r,0x09)   # each LDO CTRL EN mask 0x09
i2cw('11',0x35,0x02,0x7f)    # IOUT
i2cw('11',0x35,0x03,0x60)    # ENABLE LDO6+7
i2cw('11',0x35,0x09,0xb3)    # LDO6 VOUT 2.8V
i2cw('11',0x35,0x0a,0xb3)    # LDO7 VOUT 2.8V
time.sleep(0.3)
print('--- fan53870 after ---')
for r in (0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x09,0x0a):
    print('fan[%02x]=%s' % (r, i2c('11',0x35,r)))

print('--- wait sensor ACK (bus10 0x10) ---')
for i in range(10):
    v = i2c('10',0x10,0x0016)
    print('try%d: id16=%s' % (i, v))
    if v not in ('ERR','') and v != '0x00':
        print('SENSOR ACKED at try %d!' % i)
        break
    time.sleep(1)
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d > /tmp/v28.py && python3 /tmp/v28.py 2>&1"']
for a in range(6):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(5)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
