#!/bin/bash
set -e
H="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
for m in cam_ovl cam_genpd cam_rails cam_clk2 cam_clk cam_clk3 cam_probe_dbg; do
  if [ -f ${HOME}/fp_work/cam_pwr_mod/$m.ko ]; then
    $H "cat > /root/$m.ko" < ${HOME}/fp_work/cam_pwr_mod/$m.ko
    echo "pushed $m.ko ($(stat -c%s ${HOME}/fp_work/cam_pwr_mod/$m.ko) B)"
  fi
done
echo "=== load ==="
$H 'sh /root/cam_load.sh 2>&1 | tail -5; lsmod | grep cam_'
echo "=== cam_go ==="
$H 'sh /root/cam_go.sh 2>&1 | tail -8'
echo DONE
