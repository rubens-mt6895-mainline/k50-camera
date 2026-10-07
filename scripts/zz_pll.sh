#!/bin/sh
W=${KDIR}
echo "===== apmixedsys base ====="
grep -n -A5 "apmixedsys" $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi | head -20
echo
echo "===== mainpll / mmpll / univpll in apmixed driver ====="
ls $W/drivers/clk/mediatek/ | grep -i apmixed | grep -i 6895
echo
echo "===== MUX_HWV for CAM_SEL context (line 2555-2585) ====="
sed -n '2555,2585p' $W/drivers/clk/mediatek/clk-mt6895.c
echo
echo "===== which array is registered (cam_sel twice?) ====="
grep -n "mtk_clk_register_muxes\|mtk_clk_register_composites\|_clks\[\] =\|_clk_data" $W/drivers/clk/mediatek/clk-mt6895.c | tail -30
