#!/bin/sh
W=${KDIR}
echo "===== scpsys_domain_is_on / scpsys_pwr_con_is_on (lines 100-175) ====="
sed -n '100,175p' $W/drivers/soc/mediatek/mtk-scpsys.c
echo
echo "===== pwr_status fields in mt6895 descriptor ====="
grep -n "pwr_status\|PWR_STATUS" $W/drivers/soc/mediatek/mtk-scpsys-mt6895.c | head -20
echo
echo "----- mt6895_pwr_status array -----"
awk '/_pwr_status\[\]/,/};/' $W/drivers/soc/mediatek/mtk-scpsys-mt6895.c | head -40
echo
echo "----- mt6895_pwr_status_2nd array -----"
awk '/pwr_status_2nd\[\]/,/};/' $W/drivers/soc/mediatek/mtk-scpsys-mt6895.c | head -40
echo
echo "===== domain enum order in mtk-scpsys-mt6895.h ====="
grep -n -A40 "enum.*_domain\|MT6895_POWER_DOMAIN" $W/drivers/soc/mediatek/mtk-scpsys-mt6895.h | head -50
