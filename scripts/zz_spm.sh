#!/bin/sh
W=${KDIR}
echo "===== clk/soc mediatek files for 6895 ====="
ls $W/drivers/clk/mediatek/ | grep -i 6895
echo "---"
ls $W/drivers/soc/mediatek/ | grep -iE "6895|pm-domain"
echo
echo "===== mt6895-pm-domains.h ====="
find $W/drivers/soc/mediatek -name '*6895*domains*' -o -name '*6895*pm*' | head
for f in $(find $W/drivers/soc/mediatek -name '*6895*' | head -5); do echo "### $f"; wc -l $f; done
echo
echo "===== pwr offsets for isp/cam in mt6895 pm domains ====="
grep -rn "isp_main\|isp_vcore\|isp_dip1\|isp_ipe\|cam_main\|cam_vcore\|cam_mraw\|cam_suba" \
  $W/drivers/soc/mediatek/*6895* $W/drivers/soc/mediatek/mtk-pm-domains*.c 2>/dev/null | head -40
echo
echo "===== PWR_ / _PWR_ enum offsets ====="
grep -rn "PWR_ISP\|PWR_CAM" $W/drivers/soc/mediatek/*6895* 2>/dev/null | head -40
echo
echo "===== clk-mt6895-cam.c? ====="
ls -l $W/drivers/clk/mediatek/clk-mt6895*.c 2>/dev/null
echo
echo "===== cam_main syscon register offsets in clk driver ====="
grep -rn "0x0\|0x4\|0x8" $W/drivers/clk/mediatek/clk-mt6895-cam.c 2>/dev/null | head -20
