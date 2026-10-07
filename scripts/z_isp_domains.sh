#!/bin/bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST} 'grep -i -E "isp|cam|^domain" /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null; echo "=== cam devices runtime ==="; for d in /sys/devices/platform/1a010000.seninf* /sys/devices/platform/11c80000* /sys/devices/platform/1a0[0-9a-f]*; do [ -e "$d" ] && echo "$d: $(cat $d/power/runtime_status 2>/dev/null)"; done 2>/dev/null | head -20' > ${K50_REPO}/out/isp_domains.log 2>/dev/null
echo DONE
