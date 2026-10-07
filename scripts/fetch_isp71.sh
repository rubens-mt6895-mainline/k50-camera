#!/bin/bash
set -e
mkdir -p ${HOME}/fp_work/cam/isp71
cd ${HOME}/fp_work/cam/isp71
B='https://raw.githubusercontent.com/MotorolaMobilityLLC/kernel-mtk/android-13-release-ttt/drivers/media/platform/mtk-isp/camsys/isp7_1/cam'
for f in mtk_cam-seninf-ca.c mtk_cam-seninf-ca.h mtk_cam-seninf-def.h \
         mtk_cam-seninf-drv.c mtk_cam-seninf-drv.h mtk_cam-seninf-hw.h \
         mtk_cam-seninf-if.h mtk_cam-seninf-regs.h mtk_cam-seninf-route.c \
         mtk_cam-seninf-route.h mtk_cam-seninf.h mtk_cam-sv-regs.h \
         mtk_cam-regs.h mtk_cam-mraw-regs.h mtk_cam-defs.h; do
  curl -sL "$B/$f" -o "$f"
done
# CSI PHY dirs
for d in mtk_csi_phy_2_0 mtk_csi_phy_3_0; do
  mkdir -p "$d"
  curl -s "https://api.github.com/repos/MotorolaMobilityLLC/kernel-mtk/contents/drivers/media/platform/mtk-isp/camsys/isp7_1/cam/$d?ref=android-13-release-ttt" \
    | grep -oE '"name": "[^"]*"' | cut -d'"' -f4 | while read -r f2; do
      curl -sL "$B/$d/$f2" -o "$d/$f2"
    done
done
wc -l *.c *.h */*.c */*.h 2>/dev/null | tail -5
ls -R . | head -40
