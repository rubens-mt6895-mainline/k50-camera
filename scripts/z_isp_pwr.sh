#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'cat > /root/isp_main_power.py' < ${K50_REPO}/scripts/isp_main_power.py
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'python3 /root/isp_main_power.py > /root/isp_pwr.log 2>&1; cat /root/isp_pwr.log; echo "=== summary ==="; grep -i "isp_main" /sys/kernel/debug/pm_genpd/pm_genpd_summary' > ${K50_REPO}/out/isp_pwr.log 2>/dev/null
echo DONE
