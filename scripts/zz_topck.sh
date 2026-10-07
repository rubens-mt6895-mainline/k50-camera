#!/bin/sh
W=${KDIR}
O=${K50_REPO}/out/scp
echo "===== CLK_TOP_CAM_SEL / SENINF_SEL definitions ====="
grep -n "CLK_TOP_CAM_SEL\|CLK_TOP_SENINF_SEL\|CLK_TOP_CAM," $W/drivers/clk/mediatek/clk-mt6895.c | head -20
echo
echo "===== cam_parents / seninf_parents arrays ====="
grep -n "cam_parents\|seninf_parents" $W/drivers/clk/mediatek/clk-mt6895.c | head -10
echo "--- cam_parents body ---"
awk '/static const char \* const cam_parents/,/};/' $W/drivers/clk/mediatek/clk-mt6895.c
echo "--- seninf_parents body ---"
awk '/static const char \* const seninf_parents/,/};/' $W/drivers/clk/mediatek/clk-mt6895.c
echo
echo "===== CLK_CFG registers + UPDATE ====="
grep -n "define CLK_CFG_UPDATE\|define CLK_CFG_0\|CLK_CFG_UPDATE\b" $W/drivers/clk/mediatek/clk-mt6895.c | head -20
echo
echo "===== TOP_MUX_CAM / TOP_MUX_SENINF shift macros ====="
grep -rn "TOP_MUX_CAM\b\|TOP_MUX_CAM_SHIFT\|TOP_MUX_SENINF" $W/drivers/clk/mediatek/*.h $W/drivers/clk/mediatek/clk-mt6895.c 2>/dev/null | head -20
echo
echo "===== topckgen node in dtsi ====="
grep -n "topckgen" $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi | head -5
grep -n -A6 "topckgen: " $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi | head -12
