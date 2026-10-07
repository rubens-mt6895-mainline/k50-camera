#!/bin/sh
cd ${KDIR} || exit 1
echo "== where are MT6315 defines =="
grep -rn "define MT6315_BUCK_TOP_CON0\|define MT6315_VBUCK1\|define MT6315_BUCK_TOP_ELR0\|define MT6315_TOP2_ELR7" include/ drivers/ 2>/dev/null
echo "== mt6315 driver lines 1-60 =="
sed -n '1,60p' drivers/regulator/mt6315-regulator.c
echo "== mt6315 voltage/mode ops 150-300 =="
sed -n '150,300p' drivers/regulator/mt6315-regulator.c
echo "== mtk-spmi-pmic mt6319 cells =="
grep -n "mt6319" -A 12 drivers/mfd/mtk-spmi-pmic.c | head -60
