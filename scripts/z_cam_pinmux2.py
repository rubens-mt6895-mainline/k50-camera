import subprocess, base64, time, os

# push script via scp
local = r'${K50_REPO}\scripts\z_cam_pinmux.sh'
with open(local, 'w', encoding='utf-8') as f:
    f.write(r'''#!/bin/sh
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
echo "MARKER_START"
echo "=== pinmux-select ==="
ls -la $P/pinmux-select 2>&1
echo "=== try A: GPIO152 func1 ==="
echo "GPIO152 func1" > $P/pinmux-select 2>&1; echo "A rc=$?"
grep "pin 152" $P/pinmux-pins
echo "=== try B: 152 func1 ==="
echo "152 func1" > $P/pinmux-select 2>&1; echo "B rc=$?"
grep "pin 152" $P/pinmux-pins
echo "=== try C: 152 1 ==="
echo "152 1" > $P/pinmux-select 2>&1; echo "C rc=$?"
grep "pin 152" $P/pinmux-pins
echo "=== clocks ==="
for c in camtg3_sel camtg3_ck cam_m_camtg_con; do
  n=$(find /sys/kernel/debug/clk -maxdepth 1 -name "*$c*" 2>/dev/null | head -1)
  echo "$c: en=$(cat $n/clk_enable_count 2>/dev/null) rate=$(cat $n/clk_rate 2>/dev/null)"
done
echo "=== sensor ==="
v=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>&1 | tr -d '\n')
echo "id16=$v"
echo "MARKER_END"
''')

push = subprocess.run(['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    'scp -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no %s root@${K50_HOST}:/tmp/zpin.sh' % local.replace('\\', '/').replace('D:', '/mnt/d')],
    capture_output=True, text=True, timeout=60)
print('push rc=', push.returncode, push.stderr[-100:])

run = subprocess.run(['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "sh /tmp/zpin.sh > /tmp/zpin_out.txt 2>&1; echo DONE"'],
    capture_output=True, text=True, timeout=120)
print('run rc=', run.returncode)

pull = subprocess.run(['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    'scp -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}:/tmp/zpin_out.txt ${K50_REPO}/logs/zpin_out.txt'],
    capture_output=True, text=True, timeout=60)
print('pull rc=', pull.returncode)
with open(r'${K50_REPO}\logs\zpin_out.txt', 'r', encoding='utf-8', errors='replace') as f:
    print(f.read())
