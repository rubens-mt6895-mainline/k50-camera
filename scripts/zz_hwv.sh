#!/bin/sh
W=${KDIR}
O=${K50_REPO}/out/scp
echo "===== HWV_CLK_CFG_20 + CLK_CFG_20 defines ====="
grep -n "HWV_CLK_CFG_20\|define CLK_CFG_20\|define CLK_CFG_11\|HWV_CLK_CFG_11" $W/drivers/clk/mediatek/clk-mt6895.c
echo
echo "===== static struct mtk_mux arrays ====="
grep -n "static const struct mtk_mux" $W/drivers/clk/mediatek/clk-mt6895.c
echo
echo "===== registration calls ====="
grep -n "mtk_clk_register_muxes\|mtk_clk_register_composites\|mtk_clk_register_gates\|platform_driver\|arch_initcall" $W/drivers/clk/mediatek/clk-mt6895.c | sed -n '1,40p'
