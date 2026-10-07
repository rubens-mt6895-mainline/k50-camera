#!/bin/sh
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
H="ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no root@${K50_HOST}"

echo "== cam_main syscon 0x1a000000..0x3C =="
$H 'for o in 0 4 8 c 10 14 18 1c 20 24 28 2c 30 34 38 3c; do printf "%08x = " $((0x1a000000+o)); busybox devmem $((0x1a000000+o)) 32; done'

echo "== clk_summary: cam_lp / cam_ck / seninf =="
$H 'grep -nE "cam_lp|cam_ck|cam_sel|seninf_ck|seninf_sel|cammux|camtm_ck" /sys/kernel/debug/clk/clk_summary'

echo "== pm_genpd =="
$H 'for d in cam_main cam_mraw cam_suba cam_subb cam_subc cam_vcore isp_main isp_vcore mm_infra; do echo "$d = $(cat /sys/kernel/debug/pm_genpd/$d/current_state 2>&1)"; done'
$H 'cat /sys/kernel/debug/pm_genpd/cam_main/devices 2>&1'

echo "== WSL: scpsys subsys_lp_clk handling =="
grep -n "subsys_lp_clk\|subsys_clk\|lp_clk" ${KDIR}/drivers/soc/mediatek/mtk-scpsys.c | head -40
echo "-- cam_main descriptor --"
grep -n "cam_main\|cam_lp\|subsys_lp_clk_prefix" ${KDIR}/drivers/soc/mediatek/mtk-scpsys-mt6895.c | head -30
