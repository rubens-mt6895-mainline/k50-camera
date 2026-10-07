import subprocess, base64, time

probe = r'''
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
echo "=== pinmux-functions (152 related) ==="
grep -iE "152|mclk|cmmclk|cam" $P/pinmux-functions | head -20
echo "=== pinconf / pinmux all files ==="
ls $P
echo "=== pin 152 groups ==="
grep -B2 -A2 "152" $P/pinmux-pins | head -20
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d | sh"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode == 0 and r.stdout.strip():
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d' % r.returncode, flush=True)
    time.sleep(6)
else:
    print('FAIL')
