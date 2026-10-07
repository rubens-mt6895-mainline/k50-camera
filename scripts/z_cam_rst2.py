import subprocess, base64, time

probe = r'''
echo "=== gpiotool 155 read ==="
/root/gpiotool 155 get 2>&1 || echo "READ FAILED"
echo "=== gpiochip0 base ==="
cat /sys/kernel/debug/gpio 2>/dev/null | head -6
echo "=== set 155 high ==="
/root/gpiotool 155 1 2>&1 || echo "SET FAILED"
sleep 0.2
cat /sys/kernel/debug/gpio 2>/dev/null | grep -E "155|158|164"
echo "=== pinmux check ==="
P=$(ls -d /sys/kernel/debug/pinctrl/*pinctrl_paris 2>/dev/null | head -1)
grep -E "pin 152|pin 155" $P/pinmux-pins
echo "=== sensor ACK ==="
for i in 1 2 3 4 5; do
  v=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1 | tr -d '\n')
  echo "try$i: $v"
  [ -n "$v" ] && [ "$v" != "Error: Sending messages failed: No such device or address" ] && break
  sleep 1
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
