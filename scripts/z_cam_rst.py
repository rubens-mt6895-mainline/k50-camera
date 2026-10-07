import subprocess, base64, time

probe = r'''
P=$(ls -d /sys/kernel/debug/pinctrl/*pinctrl_paris 2>/dev/null | head -1)
echo "=== restore GPIO155 to func0 (RST pin) ==="
echo "GPIO155 func0" > $P/pinmux-select 2>&1
echo "GPIO152 func1" > $P/pinmux-select 2>&1   # keep MCLK
sleep 0.2
grep -E "pin 152|pin 155" $P/pinmux-pins
echo "=== gpio state after ==="
cat /sys/kernel/debug/gpio 2>/dev/null | grep -E "155|152|158|164"
echo "=== find gpiotool ==="
find / -name "gpiotool*" -o -name "*gpio*probe*" 2>/dev/null | grep -v proc | head -10
echo "=== try write gpio155 high via sysfs export ==="
echo 155 > /sys/class/gpio/export 2>&1 && echo "exported" || echo "export failed"
ls /sys/class/gpio/gpio155 2>/dev/null && echo "gpio155 exists"
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
