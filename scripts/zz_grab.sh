#!/bin/sh
W=${KDIR}
mkdir -p ${K50_REPO}/out/scp
cp -f $W/drivers/soc/mediatek/mtk-scpsys-mt6895.c ${K50_REPO}/out/scp/
cp -f $W/drivers/clk/mediatek/clk-mt6895-cam.c ${K50_REPO}/out/scp/
echo "copied:"; ls -l ${K50_REPO}/out/scp/
echo
echo "===== who consumes isp_main / isp_vcore / cam_main in mt6895.dtsi+rubens.dts ====="
grep -rn "isp_main\|isp_vcore\|isp_dip1\|isp_ipe\|cam_main\|cam_vcore\|cam_mraw\|cam_suba\|cam_subb\|cam_subc" \
  $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi \
  $W/arch/arm64/boot/dts/mediatek/mt6895-xiaomi-rubens.dts | head -40
echo
echo "===== power-domain id phandles ====="
grep -rn "power-domains" $W/arch/arm64/boot/dts/mediatek/mt6895.dtsi | head -30
