#!/bin/bash
KEY=$HOME/.ssh/${K50_KEY}
OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o BatchMode=yes"
HOST=root@${K50_HOST}
ssh $OPTS $HOST 'bash -s' <<'EOS'
echo "=== topckgen DT node ==="
ls -d /sys/firmware/devicetree/base/*topckgen* /sys/firmware/devicetree/base/soc\@0/*topckgen* 2>/dev/null
echo "=== clk driver DT compat ==="
grep -n "compatible" ${HOME}/work/mt6895-mainline/linux/drivers/clk/mediatek/clk-mt6895.c | head -3
grep -n "of_match\|mt6895" ${HOME}/work/mt6895-mainline/linux/drivers/clk/mediatek/clk-mt6895.c | grep -iE "of_match|compatible" | head -4
echo "=== is the topckgen driver probing? check clk owner ==="
grep -E "camtg_sel|camtm_sel" /sys/kernel/debug/clk/clk_summary | head -2
EOS