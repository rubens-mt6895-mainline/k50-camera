import subprocess, base64, time

probe = r'''
echo "=== gpio debugfs ==="
cat /sys/kernel/debug/gpio 2>/dev/null | grep -iE "670|676|158|164|vcam|rt5133|cam" | head -10
echo "=== gpio chips ==="
ls /sys/class/gpio/ 2>/dev/null | head
echo "=== gpioinfo (if present) ==="
which gpioinfo gpioset gpiodetect 2>/dev/null
echo "=== cam_rails module state ==="
lsmod | grep cam_rails
cat /proc/modules | grep cam_rails
echo "=== try read gpio via chardev ==="
ls /dev/gpiochip* 2>/dev/null
echo "=== pinctrl 670/676 ==="
P=$(ls -d /sys/kernel/debug/pinctrl/*pinctrl_paris 2>/dev/null | head -1)
grep -E "670|676" $P/pinmux-pins 2>/dev/null | head -6
echo "=== i2c bus11 scan ==="
i2cdetect -y 11 2>&1 | head -8
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d | sh 2>&1"']
for a in range(6):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(5)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
