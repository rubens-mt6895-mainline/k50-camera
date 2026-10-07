import subprocess, base64, time

with open(r'${K50_REPO}\scripts\z_cam_ro_dump.py', 'rb') as f:
    b64 = base64.b64encode(f.read()).decode()

cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    f'ssh -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${K50_HOST} "echo {b64} | base64 -d > /tmp/z_ro.py && python3 /tmp/z_ro.py > /tmp/z_ro_out.txt 2>&1"']
ok = False
for attempt in range(5):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode == 0:
        ok = True
        break
    time.sleep(3)
if not ok:
    print('RUN FAIL', r.stdout[-200:], r.stderr[-200:])
pull = subprocess.run(['wsl', '-d', 'Ubuntu', '--', 'bash', '-lc',
    'scp -i ${HOME}/.ssh/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}:/tmp/z_ro_out.txt ${K50_REPO}/logs/z_cam_ro_out.txt && echo PULL_OK'],
    capture_output=True, text=True, timeout=120)
print('PULL:', pull.stdout[-80:], pull.stderr[-80:])
with open(r'${K50_REPO}\logs\z_cam_ro_out.txt', 'r', encoding='utf-8', errors='replace') as f:
    print(f.read())
