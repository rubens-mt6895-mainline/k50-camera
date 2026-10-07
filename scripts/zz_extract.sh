#!/bin/sh
W=${KDIR}
O=${K50_REPO}/out/scp
sed -n '690,770p' $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi > $O/spm_clocks.txt
sed -n '1400,1430p' $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi > $O/omitted.txt
sed -n '3250,3300p' $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi > $O/camsys_syscons.txt
sed -n '100,180p' $W/drivers/soc/mediatek/mtk-scpsys-mt6895.c > $O/isp_desc.txt
sed -n '240,330p' $W/drivers/soc/mediatek/mtk-scpsys-mt6895.c > $O/cam_desc.txt
sed -n '1,60p' $W/drivers/soc/mediatek/mtk-scpsys-mt6895.c > $O/scpsys_head.txt
echo done; wc -l $O/*.txt
