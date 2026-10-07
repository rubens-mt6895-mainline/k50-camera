#!/bin/sh
echo "== WSL trees =="
ls -la ${HOME}/work/
echo "== kernel.release per tree =="
for t in ${HOME}/work/*/; do
  if [ -f "$t/include/config/kernel.release" ]; then
    echo -n "$t -> "; cat "$t/include/config/kernel.release"
  fi
done
echo "== device uname + existing module vermagic =="
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} 'uname -a; echo ---; for m in /root/cam_mmtest.ko /root/cam_clk.ko /root/cam_cap.ko; do echo "-- $m"; strings $m 2>/dev/null | grep -m1 vermagic; done; echo "--- /root ko list"; ls -la /root/*.ko 2>/dev/null'
