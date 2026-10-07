#!/bin/bash
H="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=25 -i ~/.ssh/${K50_KEY} root@${K50_HOST}"
$H 'for c in camtg_ck camtg1_ck camtg2_ck camtg3_ck camtg4_ck camtg5_ck camtg6_ck camtg7_ck camtg_sel camtg1_sel camtg2_sel camtg3_sel camtg4_sel camtg5_sel camtg6_sel camtg7_sel; do p=/sys/kernel/debug/clk/$c; [ -d $p ] && printf "%-12s en=%-3s prep=%-3s rate=%s\n" $c "$(cat $p/clk_enable_count 2>/dev/null)" "$(cat $p/clk_prepare_count 2>/dev/null)" "$(cat $p/clk_rate 2>/dev/null)"; done'
echo DONE
