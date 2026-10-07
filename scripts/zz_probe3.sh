#!/bin/sh
TREE=${KDIR}
echo "######## topckgen: how cam_ck / cam_sel / seninf are defined ########"
grep -n 'cam_ck\|cam_sel\|campll\|cam_pll\|seninf_ck\|seninf_sel\|camtm_ck\|cam_dig' $TREE/drivers/clk/mediatek/clk-mt6895.c | head -40
echo "######## clk-mt6895.c: driver registration style ########"
grep -n 'clk_register\|of_clk_add_provider\|CLK_OF_DECLARE\|mtk_clk_register\|platform_driver\|module_platform\|builtin_platform\|postcore_initcall\|arch_initcall' $TREE/drivers/clk/mediatek/clk-mt6895.c | head -30
cp -f ${WINHOME}/.ssh/${K50_KEY} /tmp/${K50_KEY} 2>/dev/null
chmod 600 /tmp/${K50_KEY}
ssh -i /tmp/${K50_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@${K50_HOST} '
echo "== clk_summary hierarchy 620-700 =="
sed -n "620,700p" /sys/kernel/debug/clk/clk_summary
echo "== regulators matching cam/vmm/isp/dvfs =="
grep -iE "cam|vmm|isp|dvfs|vcam" /sys/kernel/debug/regulator/regulator_summary
echo "== regulator count =="
grep -c . /sys/kernel/debug/regulator/regulator_summary
echo "== dvfsrc debugfs =="
ls /sys/kernel/debug/ | grep -iE "dvfs|vmm|scpsys|pm_genpd|clk"
'
