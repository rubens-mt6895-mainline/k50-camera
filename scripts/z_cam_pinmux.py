import subprocess, base64, time

probe = r'''
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
echo "=== pinmux-select file type ==="
ls -la $P/pinmux-select 2>&1
echo "=== try formats ==="
echo "GPIO152 func1" > $P/pinmux-select 2>&1; echo "A rc=$?"
grep "pin 152" $P/pinmux-pins
echo "152 1" > $P/pinmux-select 2>&1; echo "B rc=$?"
grep "pin 152" $P/pinmux-pins
echo "152 func1" > $P/pinmux-select 2>&1; echo "C rc=$?"
grep "pin 152" $P/pinmux-pins
echo "=== read back pinmux-select usage ==="
head -c 300 $P/pinmux-select 2>&1 | od -c | head -5
echo "=== dmesg pinmux tail ==="
dmesg | tail -20 | grep -iE "pinmux|pinctrl|152" 
echo "=== clock tree still on? ==="
for c in camtg3_sel camtg3_ck cam_m_camtg_con; do
  n=$(find /sys/kernel/debug/clk -maxdepth 1 -name "*$c*" 2>/dev/null | head -1)
  echo "$c: en=$(cat $n/clk_enable_count 2>/dev/null) rate=$(cat $n/clk_rate 2>/dev/null)"
done
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
