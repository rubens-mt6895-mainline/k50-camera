#!/bin/sh
W=${KDIR}
echo "===== mtk-scpsys.c: is_on / power_on / power_off / BYPASS_INIT_ON ====="
grep -n "sta_mask\|BYPASS_INIT_ON\|IS_PWR_CON_ON\|_is_on\|power_on\|power_off\|PWR_STA\|bus_protect\|BUS_PROT" $W/drivers/soc/mediatek/mtk-scpsys.c | head -60
echo
echo "----- is_on function -----"
awk '/static bool mtk_scpsys_domain_is_on/,/^}/' $W/drivers/soc/mediatek/mtk-scpsys.c
echo
echo "----- power_on function -----"
awk '/static int scpsys_power_on/,/^}/' $W/drivers/soc/mediatek/mtk-scpsys.c | head -80
echo
echo "===== caps definitions ====="
grep -n -B2 -A8 "MTK_SCPD_BYPASS_INIT_ON\s*=\|#define MTK_SCPD" $W/drivers/soc/mediatek/mtk-scpsys.h | head -60
echo
echo "===== does mt6895.dtsi have pda/seninf/camsv nodes? ====="
grep -n "pda@\|seninf@\|seninf_top\|camsv\|camisp@\|camera-pda\|mraw@" $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi | head -30
echo
echo "===== rubens dts: cam mentions ====="
grep -n "pda\|seninf\|camsv\|camisp\|mraw\|camera" $W/arch/arm64/boot/dts/mediatek/mt6895-xiaomi-rubens.dts | head -30
