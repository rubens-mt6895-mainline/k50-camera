#!/bin/sh
W=${KDIR}
echo "===== PLL CON0 offsets ====="
grep -n "define MAINPLL_CON\|define UNIVPLL_CON\|define MMPLL_CON\|define APLL1_CON\|define APLL2_CON" $W/drivers/clk/mediatek/clk-mt6895.c
echo
echo "===== apmixed_plls entries (2800-2860) ====="
sed -n '2800,2860p' $W/drivers/clk/mediatek/clk-mt6895.c
echo
echo "===== hwv node ====="
grep -n -A6 "hwv:" $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi | head -12
grep -n "HWV.*0x\|hwv" $W/drivers/clk/mediatek/clk-mt6895.c | head -12
