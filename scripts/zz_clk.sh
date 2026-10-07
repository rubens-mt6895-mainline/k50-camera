#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H=root@${K50_HOST}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$H" '
uptime
echo "=== cam subtree in clk_summary ==="
grep -nE "cam_ck|camtm_ck|camsel|seninf|cam_m_|cam_lp|camtg" /sys/kernel/debug/clk/clk_summary
echo "=== pm_genpd cam/isp ==="
for d in /sys/kernel/debug/pm_genpd/*; do
  n=$(basename $d)
  case "$n" in
    cam*|isp*|mm_infra*) echo "--- $n"; cat $d/current_state 2>/dev/null; head -5 $d/devices 2>/dev/null;;
  esac
done
'
