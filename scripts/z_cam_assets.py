import subprocess, base64, time

probe = r'''
echo "=== cam modules on disk ==="
ls -la /home/k50/*.ko /opt/*.ko /lib/modules/*/extra/*.ko 2>/dev/null | head -20
echo "=== loaded ==="
lsmod | grep -E "cam|mclk|fan|pwr"
echo "=== clk camtg ==="
for c in camtg_sel camtg2_sel camtg3_sel camtg_ck camtg2_ck camtg3_ck cam_m_camtg_con; do
  n=$(find /sys/kernel/debug/clk -maxdepth 1 -name "*$c*" 2>/dev/null | head -1)
  if [ -n "$n" ]; then echo "$c: enable=$(cat $n/clk_enable_count 2>/dev/null) rate=$(cat $n/clk_rate 2>/dev/null)"; else echo "$c: NOT FOUND"; fi
done
echo "=== cam gpios ==="
for g in 158 149 20 159 164 670 676 152 155; do
  d=/sys/class/gpio/gpio$g
  if [ -d "$d" ]; then echo "gpio$g: dir=$(cat $d/direction 2>/dev/null) val=$(cat $d/value 2>/dev/null)"; else echo "gpio$g: no sysfs"; fi
done
echo "=== fan53870 full ==="
for r in 00 01 02 03 04 05 06 09 0a 13 14 15; do
  v=$(i2ctransfer -f -y 11 w2@0x35 0x$r r1 2>&1); echo "fan[$r]=$v"
done
echo "=== pinmux 152/155 ==="
cat /sys/kernel/debug/pinctrl/*/pinmux-pins 2>/dev/null | grep -E "pin 152|pin 155|\(152|\(155" | head -5
'''
pb = base64.b64encode(probe.encode()).decode()
cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {pb} | base64 -d | sh 2>&1"']
for a in range(4):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode == 0:
        print(r.stdout)
        if r.stderr: print('ERR:', r.stderr[-200:])
        break
    time.sleep(4)
else:
    print('FAIL', r.stdout[-200:], r.stderr[-200:])
