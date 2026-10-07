import subprocess, time

local = r'${K50_REPO}\scripts\z_cam_pinmux3.sh'
with open(local, 'w', encoding='utf-8', newline='\n') as f:
    f.write('''#!/bin/sh
P=/sys/kernel/debug/pinctrl/10005000.pinctrl-pinctrl_paris
echo "MARKER_START"
echo "tryA:"
echo "GPIO152 func1" > $P/pinmux-select
echo "rcA=$?"
grep "pin 152" $P/pinmux-pins
echo "tryB:"
echo "152 func1" > $P/pinmux-select
echo "rcB=$?"
grep "pin 152" $P/pinmux-pins
echo "tryC:"
echo "152 1" > $P/pinmux-select
echo "rcC=$?"
grep "pin 152" $P/pinmux-pins
echo "clocks:"
for c in camtg3_sel camtg3_ck cam_m_camtg_con; do
  n=$(find /sys/kernel/debug/clk -maxdepth 1 -name "*$c*" 2>/dev/null | head -1)
  echo "$c: en=$(cat $n/clk_enable_count 2>/dev/null) rate=$(cat $n/clk_rate 2>/dev/null)"
done
echo "sensor:"
v=$(i2ctransfer -f -y 10 w2@0x10 0x00 0x16 r1 2>/dev/null | tr -d '\n')
echo "id16=$v"
echo "MARKER_END"
''')

def ssh_exec(remote_cmd, timeout=120):
    r = subprocess.run(['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc', remote_cmd],
                       capture_output=True, text=True, timeout=timeout)
    return r

lp = local.replace('\\', '/').replace('D:', '/mnt/d')
for a in range(5):
    r = ssh_exec(f'scp -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no {lp} root@${K50_HOST}:/tmp/zpin3.sh && ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "sh /tmp/zpin3.sh > /tmp/zpin3_out.txt 2>/dev/null; echo DONE_$? && cat /tmp/zpin3_out.txt"')
    if r.returncode == 0 and 'MARKER_END' in r.stdout:
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d out=%r' % (r.returncode, r.stdout[-60:]), flush=True)
    time.sleep(5)
else:
    print('FAIL')
