import subprocess, base64, time

with open(r'${K50_REPO}\scripts\z_cam_pinmux3.sh', 'rb') as f:
    b64 = base64.b64encode(f.read()).decode()

cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {b64} | base64 -d > /tmp/zpin3.sh && sh /tmp/zpin3.sh"']
for a in range(8):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode == 0 and 'MARKER_END' in r.stdout:
        print(r.stdout)
        break
    print('  retry', a, 'rc=%d out=%r' % (r.returncode, r.stdout[-80:]), flush=True)
    time.sleep(6)
else:
    print('FAIL', r.stdout[-300:], r.stderr[-300:])
