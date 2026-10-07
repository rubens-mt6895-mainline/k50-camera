import subprocess, base64, time

probe = r'''
echo "=== uptime ==="
uptime
echo "=== cam modules ==="
lsmod | grep -E "cam_"
echo "=== i2c scan bus10 ==="
i2cdetect -y -l 2>/dev/null | head -5
i2cdetect -y 10 2>&1 | head -8
echo "=== fan53870 ==="
for r in 03 09 0a; do
  echo "fan[$r]=$(i2ctransfer -f -y 11 w2@0x35 0x$r r1 2>&1 | tr -d '\n')"
done
echo "=== sensor 0100 x3 ==="
for i in 1 2 3; do
  echo "try$i: $(i2ctransfer -f -y 10 w2@0x10 0x01 0x00 r1 2>&1 | tr -d '\n')"
  sleep 1
done
echo "=== clk quick ==="
for c in camtg3_sel cam_m_seninf_con; do
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
