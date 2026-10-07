#!/bin/bash
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$SSH '
echo "== cam_go.sh full =="
cat /root/cam_go.sh
echo "== clk enable counts =="
for c in camtg1_ck camtg2_ck camtg3_ck camtg4_ck camtg5_ck camtg6_ck; do
  echo -n "$c: en="
  cat /sys/kernel/debug/clk/$c/clk_enable_count 2>/dev/null || echo NA
  echo -n " rate="
  cat /sys/kernel/debug/clk/$c/clk_rate 2>/dev/null || echo NA
done
' > ${K50_REPO}/out/camgo_full.log 2>&1
echo DONE
