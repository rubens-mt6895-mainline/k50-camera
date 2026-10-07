import subprocess, time

def ssh(cmd, timeout=60):
    for attempt in range(3):
        try:
            r = subprocess.run(['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
                f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "{cmd}"'],
                capture_output=True, text=True, timeout=timeout)
            if r.returncode == 0:
                return r.stdout
        except Exception as e:
            pass
        time.sleep(3)
    return None

# 1. device online + cam modules
out = ssh('echo ONLINE; lsmod | grep -E "cam_|mtk_cam|isp" ; echo ---; cat /sys/kernel/debug/pinctrl/*/pinmux-pins 2>/dev/null | head -1; uname -r')
print('== ONLINE/Modules ==')
print(out or 'NO RESPONSE')

# 2. sensor streaming state (read-only i2c)
out2 = ssh('i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1; echo ---; i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1; echo ---; i2ctransfer -f -y 10 w2@0x10 0x00 0x17 r1 2>&1')
print('== Sensor ==')
print(out2 or 'NO RESPONSE')

# 3. cam MMIO liveness + CSI2 state (devmem read-only)
out3 = ssh('for a in 0x1a000000 0x1a014adc 0x1a014a00 0x11c86000 0x11c86030 0x11c86034; do echo -n "$a = "; devmem2 $a 2>/dev/null || busybox devmem $a 2>/dev/null || echo "devmem2 missing"; done; which devmem2 busybox')
print('== MMIO ==')
print(out3 or 'NO RESPONSE')
